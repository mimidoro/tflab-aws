// tflab API - .NET minimal API over PostgreSQL with IAM database authentication.
// No passwords: the pod's EKS Pod Identity credentials sign a 15-minute RDS auth token.
//
//   GET    /api/healthz      process liveness (ALB target health, k8s probes)
//   GET    /api/ready        database reachable? writable? (Route 53 failover health check)
//   GET    /api/info         region / pod / node / role - shows which region served you
//   GET    /api/items        latest 50 items
//   GET    /api/items/{id}
//   POST   /api/items        { "text": "..." }  -> 201; 503 when this region is a read-only standby
//   DELETE /api/items/{id}
//
//   Api --db-init           one-shot schema + tflab_api role bootstrap (Helm pre-install hook)

using System.Text.Json;
using System.Text.RegularExpressions;
using Amazon;
using Amazon.RDS.Util;
using Amazon.SecretsManager;
using Amazon.SecretsManager.Model;
using Npgsql;

var cfg = LabConfig.FromEnvironment();

if (args.Contains("--db-init"))
{
    return await DbInit.RunAsync(cfg);
}

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.UseUrls("http://0.0.0.0:8080");
builder.Logging.AddJsonConsole();
builder.Services.AddSingleton(cfg);
builder.Services.AddSingleton(_ => Db.CreateIamDataSource(cfg));

var app = builder.Build();
var api = app.MapGroup("/api");

api.MapGet("/healthz", () => Results.Ok(new { status = "ok" }));

api.MapGet("/ready", async (NpgsqlDataSource db, CancellationToken ct) =>
{
    try
    {
        await using var cmd = db.CreateCommand("SELECT pg_is_in_recovery()");
        var inRecovery = (bool)(await cmd.ExecuteScalarAsync(ct))!;
        return Results.Ok(new { db = "ok", writable = !inRecovery, region = cfg.RegionLabel });
    }
    catch (Exception ex)
    {
        app.Logger.LogWarning(ex, "Readiness check failed");
        return Results.Json(new { db = "unreachable", region = cfg.RegionLabel }, statusCode: 503);
    }
});

api.MapGet("/info", async (NpgsqlDataSource db, CancellationToken ct) =>
{
    bool? writable = null;
    try
    {
        await using var cmd = db.CreateCommand("SELECT NOT pg_is_in_recovery()");
        writable = (bool)(await cmd.ExecuteScalarAsync(ct))!;
    }
    catch (Exception ex)
    {
        app.Logger.LogWarning(ex, "Info: database unreachable");
    }

    return Results.Ok(new
    {
        region = cfg.RegionLabel,
        awsRegion = cfg.AwsRegion,
        configuredRole = cfg.IsPrimaryRegion ? "primary" : "standby",
        dbWritable = writable,
        pod = Environment.GetEnvironmentVariable("POD_NAME"),
        node = Environment.GetEnvironmentVariable("NODE_NAME"),
        version = Environment.GetEnvironmentVariable("APP_VERSION") ?? "dev",
    });
});

api.MapGet("/items", async (NpgsqlDataSource db, CancellationToken ct) =>
{
    await using var cmd = db.CreateCommand(
        "SELECT id, text, region, created_at FROM items ORDER BY id DESC LIMIT 50");
    await using var reader = await cmd.ExecuteReaderAsync(ct);
    var items = new List<Item>();
    while (await reader.ReadAsync(ct))
    {
        items.Add(Item.From(reader));
    }
    return Results.Ok(items);
});

api.MapGet("/items/{id:long}", async (long id, NpgsqlDataSource db, CancellationToken ct) =>
{
    await using var cmd = db.CreateCommand("SELECT id, text, region, created_at FROM items WHERE id = $1");
    cmd.Parameters.AddWithValue(id);
    await using var reader = await cmd.ExecuteReaderAsync(ct);
    return await reader.ReadAsync(ct) ? Results.Ok(Item.From(reader)) : Results.NotFound();
});

api.MapPost("/items", async (NewItem body, NpgsqlDataSource db, CancellationToken ct) =>
{
    var text = body.Text?.Trim() ?? "";
    if (text.Length is < 1 or > 200)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]>
        {
            ["text"] = ["Text must be 1-200 characters."],
        });
    }

    try
    {
        await using var cmd = db.CreateCommand(
            "INSERT INTO items (text, region) VALUES ($1, $2) RETURNING id, text, region, created_at");
        cmd.Parameters.AddWithValue(text);
        cmd.Parameters.AddWithValue(cfg.RegionLabel);
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        await reader.ReadAsync(ct);
        var item = Item.From(reader);
        return Results.Created($"/api/items/{item.Id}", item);
    }
    catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.ReadOnlySqlTransaction)
    {
        return Results.Json(
            new { error = "This region is a read-only standby. Promote the replica to accept writes." },
            statusCode: 503);
    }
});

api.MapDelete("/items/{id:long}", async (long id, NpgsqlDataSource db, CancellationToken ct) =>
{
    try
    {
        await using var cmd = db.CreateCommand("DELETE FROM items WHERE id = $1");
        cmd.Parameters.AddWithValue(id);
        return await cmd.ExecuteNonQueryAsync(ct) > 0 ? Results.NoContent() : Results.NotFound();
    }
    catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.ReadOnlySqlTransaction)
    {
        return Results.Json(new { error = "read-only standby" }, statusCode: 503);
    }
});

await app.RunAsync();
return 0;

// ---------------------------------------------------------------------------------------------

public sealed record NewItem(string? Text);

public sealed record Item(long Id, string Text, string Region, DateTime CreatedAt)
{
    public static Item From(NpgsqlDataReader r) =>
        new(r.GetInt64(0), r.GetString(1), r.GetString(2), r.GetDateTime(3));
}

public sealed record LabConfig(
    string RegionLabel, bool IsPrimaryRegion, string AwsRegion,
    string DbHost, string DbName, string DbUser, string? MasterSecretArn)
{
    public static LabConfig FromEnvironment()
    {
        static string Req(string name) =>
            Environment.GetEnvironmentVariable(name) is { Length: > 0 } v
                ? v
                : throw new InvalidOperationException($"Missing required environment variable {name}");

        var user = Req("DB_USER");
        if (!Regex.IsMatch(user, "^[a-z_][a-z0-9_]{0,62}$"))
        {
            throw new InvalidOperationException("DB_USER must be a simple lower-case identifier");
        }

        return new LabConfig(
            RegionLabel: Environment.GetEnvironmentVariable("REGION_LABEL") ?? "unknown",
            IsPrimaryRegion: string.Equals(Environment.GetEnvironmentVariable("IS_PRIMARY_REGION"), "true", StringComparison.OrdinalIgnoreCase),
            AwsRegion: Req("AWS_REGION"),
            DbHost: Req("DB_HOST"),
            DbName: Req("DB_NAME"),
            DbUser: user,
            MasterSecretArn: Environment.GetEnvironmentVariable("DB_MASTER_SECRET_ARN"));
    }
}

public static class Db
{
    // Amazon RDS global CA bundle baked into the image (see Dockerfile) for full TLS verification.
    private const string RdsCaBundle = "/etc/ssl/rds/global-bundle.pem";

    private static NpgsqlConnectionStringBuilder BaseConnectionString(LabConfig cfg, string user) => new()
    {
        Host = cfg.DbHost,
        Port = 5432,
        Database = cfg.DbName,
        Username = user,
        SslMode = SslMode.VerifyFull,
        RootCertificate = RdsCaBundle,
        Timeout = 5,
        CommandTimeout = 5,
        MaxPoolSize = 20,
    };

    public static NpgsqlDataSource CreateIamDataSource(LabConfig cfg)
    {
        var builder = new NpgsqlDataSourceBuilder(BaseConnectionString(cfg, cfg.DbUser).ConnectionString);
        var region = RegionEndpoint.GetBySystemName(cfg.AwsRegion);

        // Tokens live 15 minutes; refresh every 10, retry quickly on failure.
        builder.UsePeriodicPasswordProvider(
            (_, _) => ValueTask.FromResult(
                RDSAuthTokenGenerator.GenerateAuthToken(region, cfg.DbHost, 5432, cfg.DbUser)),
            TimeSpan.FromMinutes(10),
            TimeSpan.FromSeconds(5));

        return builder.Build();
    }

    public static NpgsqlDataSource CreatePasswordDataSource(LabConfig cfg, string user, string password)
    {
        var csb = BaseConnectionString(cfg, user);
        csb.Password = password;
        return NpgsqlDataSource.Create(csb.ConnectionString);
    }
}

public static class DbInit
{
    public static async Task<int> RunAsync(LabConfig cfg)
    {
        if (string.IsNullOrEmpty(cfg.MasterSecretArn))
        {
            Console.Error.WriteLine("db-init: DB_MASTER_SECRET_ARN not set (only runs in the primary region)");
            return 2;
        }

        using var sm = new AmazonSecretsManagerClient(RegionEndpoint.GetBySystemName(cfg.AwsRegion));
        var secret = await sm.GetSecretValueAsync(new GetSecretValueRequest { SecretId = cfg.MasterSecretArn });
        using var json = JsonDocument.Parse(secret.SecretString);
        var masterUser = json.RootElement.GetProperty("username").GetString()!;
        var masterPassword = json.RootElement.GetProperty("password").GetString()!;

        await using var db = Db.CreatePasswordDataSource(cfg, masterUser, masterPassword);

        // DB_USER is validated as a plain identifier in LabConfig, so interpolation is safe here.
        var sql = $"""
            DO $$
            BEGIN
              IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '{cfg.DbUser}') THEN
                CREATE ROLE {cfg.DbUser} LOGIN;
              END IF;
            END
            $$;
            GRANT rds_iam TO {cfg.DbUser};
            CREATE TABLE IF NOT EXISTS items (
              id         bigserial    PRIMARY KEY,
              text       varchar(200) NOT NULL,
              region     text         NOT NULL,
              created_at timestamptz  NOT NULL DEFAULT now()
            );
            GRANT SELECT, INSERT, DELETE ON items TO {cfg.DbUser};
            GRANT USAGE, SELECT ON SEQUENCE items_id_seq TO {cfg.DbUser};
            """;

        for (var attempt = 1; ; attempt++)
        {
            try
            {
                await using var cmd = db.CreateCommand(sql);
                await cmd.ExecuteNonQueryAsync();
                Console.WriteLine($"db-init: role {cfg.DbUser} and schema ready");
                return 0;
            }
            catch (Exception ex) when (attempt < 30)
            {
                Console.Error.WriteLine($"db-init: attempt {attempt} failed ({ex.Message}); retrying in 10s");
                await Task.Delay(TimeSpan.FromSeconds(10));
            }
        }
    }
}
