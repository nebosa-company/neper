/* The e.db benchmark's workload written directly against each C API, as the baseline the Neper
 * drivers are measured against. Each backend uses the same strategy as its Neper driver, so
 * the difference is the driver's own cost:
 *   sqlite      prepared statements, bind and step
 *   postgresql  binary parameters and binary results, single-row mode for the scan
 *   mysql       text protocol: parameters escaped into the statement, mysql_use_result
 *   odbc        the wide entry points, prepared statements with bound parameters, SQLFetch
 *               and SQLGetData per column, text as UTF-16
 *
 *   bench-c sqlite <file> <rows> <lookups>
 *   bench-c postgresql <conninfo> <rows> <lookups>
 *   bench-c mysql <port> <rows> <lookups>
 *   bench-c odbc <connection string> <rows> <lookups>
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#include <winsqlite/winsqlite3.h>
#else
#include <time.h>
#include <sqlite3.h>
#endif
#include <libpq-fe.h>
#include <mysql.h>
#include <sql.h>
#include <sqlext.h>

static const char *NAMES[16] = { "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel",
                                 "india", "juliett", "kilo", "lima", "mike", "november", "oscar", "papa" };

static int64_t now_ns(void) {
#ifdef _WIN32
    LARGE_INTEGER f, c;
    QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&c);
    return (int64_t)((double)c.QuadPart * 1e9 / (double)f.QuadPart);
#else
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (int64_t)t.tv_sec * 1000000000 + t.tv_nsec;
#endif
}

static void die(const char *what) { fprintf(stderr, "bench-c: %s\n", what); exit(1); }

static uint64_t be64(uint64_t v) {
    uint64_t r = 0;
    for (int i = 0; i < 8; i++) r = (r << 8) | ((v >> (i * 8)) & 0xff);
    return r;
}

/* ---- sqlite */
static void run_sqlite(const char *path, int64_t rows, int64_t lookups) {
    sqlite3 *db;
    sqlite3_stmt *st;
    if (sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL) != SQLITE_OK) die("sqlite open");
    sqlite3_exec(db, "DROP TABLE IF EXISTS bench", 0, 0, 0);
    if (sqlite3_exec(db, "CREATE TABLE bench(id BIGINT PRIMARY KEY, name VARCHAR(32) NOT NULL, score DOUBLE PRECISION NOT NULL)", 0, 0, 0)) die("sqlite create");
    int64_t t0 = now_ns();
    sqlite3_exec(db, "BEGIN", 0, 0, 0);
    sqlite3_prepare_v2(db, "INSERT INTO bench VALUES (?, ?, ?)", -1, &st, 0);
    for (int64_t i = 0; i < rows; i++) {
        sqlite3_bind_int64(st, 1, i);
        sqlite3_bind_text(st, 2, NAMES[i % 16], -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(st, 3, (double)i * 0.5);
        if (sqlite3_step(st) != SQLITE_DONE) die("sqlite insert");
        sqlite3_reset(st);
    }
    sqlite3_finalize(st);
    sqlite3_exec(db, "COMMIT", 0, 0, 0);
    int64_t insert_ns = now_ns() - t0;

    t0 = now_ns();
    sqlite3_prepare_v2(db, "SELECT id, name, score FROM bench", -1, &st, 0);
    int64_t count = 0, sum = 0, bytes = 0;
    while (sqlite3_step(st) == SQLITE_ROW) {
        sum += sqlite3_column_int64(st, 0);
        const unsigned char *name = sqlite3_column_text(st, 1);
        bytes += sqlite3_column_bytes(st, 1) + (name ? 0 : 0);
        volatile double score = sqlite3_column_double(st, 2);
        (void)score;
        count++;
    }
    sqlite3_finalize(st);
    int64_t scan_ns = now_ns() - t0;
    if (count != rows || sum != rows * (rows - 1) / 2) die("sqlite scan");

    t0 = now_ns();
    sqlite3_prepare_v2(db, "SELECT name, score FROM bench WHERE id = ?", -1, &st, 0);
    int64_t found = 0;
    for (int64_t j = 0; j < lookups; j++) {
        sqlite3_bind_int64(st, 1, (j * 7919) % rows);
        if (sqlite3_step(st) == SQLITE_ROW) {
            volatile int n = sqlite3_column_bytes(st, 0);
            (void)n;
            found++;
        }
        sqlite3_reset(st);
    }
    sqlite3_finalize(st);
    int64_t lookup_ns = now_ns() - t0;
    if (found != lookups) die("sqlite lookup");
    sqlite3_close_v2(db);
    printf("sqlite insert_ns=%lld scan_ns=%lld lookup_ns=%lld\n", (long long)insert_ns, (long long)scan_ns, (long long)lookup_ns);
}

/* ---- postgresql */
static void pg_ok(PGresult *r, const char *what) {
    ExecStatusType s = PQresultStatus(r);
    if (s != PGRES_COMMAND_OK && s != PGRES_TUPLES_OK && s != PGRES_SINGLE_TUPLE) { fprintf(stderr, "%s", PQresultErrorMessage(r)); die(what); }
}

static void run_postgresql(const char *conninfo, int64_t rows, int64_t lookups) {
    PGconn *c = PQconnectdb(conninfo);
    if (PQstatus(c) != CONNECTION_OK) die("pg connect");
    PGresult *r = PQexec(c, "DROP TABLE IF EXISTS bench");
    PQclear(r);
    r = PQexec(c, "CREATE TABLE bench(id BIGINT PRIMARY KEY, name VARCHAR(32) NOT NULL, score DOUBLE PRECISION NOT NULL)");
    pg_ok(r, "pg create");
    PQclear(r);
    int64_t t0 = now_ns();
    PQclear(PQexec(c, "BEGIN"));
    r = PQprepare(c, "ins", "INSERT INTO bench VALUES ($1, $2, $3)", 0, NULL);
    pg_ok(r, "pg prepare");
    PQclear(r);
    for (int64_t i = 0; i < rows; i++) {
        uint64_t id = be64((uint64_t)i);
        double d = (double)i * 0.5;
        uint64_t bits;
        memcpy(&bits, &d, 8);
        bits = be64(bits);
        const char *values[3] = { (const char *)&id, NAMES[i % 16], (const char *)&bits };
        int lengths[3] = { 8, (int)strlen(NAMES[i % 16]), 8 };
        int formats[3] = { 1, 0, 1 };
        r = PQexecPrepared(c, "ins", 3, values, lengths, formats, 1);
        pg_ok(r, "pg insert");
        PQclear(r);
    }
    PQclear(PQexec(c, "COMMIT"));
    int64_t insert_ns = now_ns() - t0;

    t0 = now_ns();
    if (!PQsendQueryParams(c, "SELECT id, name, score FROM bench", 0, NULL, NULL, NULL, NULL, 1)) die("pg send");
    PQsetSingleRowMode(c);
    int64_t count = 0, sum = 0, bytes = 0;
    while ((r = PQgetResult(c)) != NULL) {
        if (PQresultStatus(r) == PGRES_SINGLE_TUPLE) {
            uint64_t raw;
            memcpy(&raw, PQgetvalue(r, 0, 0), 8);
            sum += (int64_t)be64(raw);
            bytes += PQgetlength(r, 0, 1);
            memcpy(&raw, PQgetvalue(r, 0, 2), 8);
            count++;
        }
        PQclear(r);
    }
    int64_t scan_ns = now_ns() - t0;
    if (count != rows || sum != rows * (rows - 1) / 2) die("pg scan");

    t0 = now_ns();
    r = PQprepare(c, "sel", "SELECT name, score FROM bench WHERE id = $1", 0, NULL);
    pg_ok(r, "pg prepare select");
    PQclear(r);
    int64_t found = 0;
    for (int64_t j = 0; j < lookups; j++) {
        uint64_t id = be64((uint64_t)((j * 7919) % rows));
        const char *values[1] = { (const char *)&id };
        int lengths[1] = { 8 };
        int formats[1] = { 1 };
        r = PQexecPrepared(c, "sel", 1, values, lengths, formats, 1);
        if (PQntuples(r) == 1) found++;
        PQclear(r);
    }
    int64_t lookup_ns = now_ns() - t0;
    if (found != lookups) die("pg lookup");
    PQfinish(c);
    printf("postgresql insert_ns=%lld scan_ns=%lld lookup_ns=%lld\n", (long long)insert_ns, (long long)scan_ns, (long long)lookup_ns);
}

/* ---- mysql */
static void my_query(MYSQL *m, const char *q, const char *what) {
    if (mysql_real_query(m, q, (unsigned long)strlen(q))) { fprintf(stderr, "%s\n", mysql_error(m)); die(what); }
}

static void run_mysql(unsigned port, int64_t rows, int64_t lookups) {
    MYSQL *m = mysql_init(NULL);
    mysql_options(m, MYSQL_SET_CHARSET_NAME, "utf8mb4");
    /* The same connection options the Neper driver uses. */
    if (!mysql_real_connect(m, "127.0.0.1", "root", "", "neper", port, NULL, CLIENT_MULTI_STATEMENTS | CLIENT_MULTI_RESULTS)) die("mysql connect");
    my_query(m, "SET time_zone = '+00:00'", "mysql zone");
    my_query(m, "DROP TABLE IF EXISTS bench", "mysql drop");
    my_query(m, "CREATE TABLE bench(id BIGINT PRIMARY KEY, name VARCHAR(32) NOT NULL, score DOUBLE PRECISION NOT NULL)", "mysql create");
    char q[256], escaped[64];
    int64_t t0 = now_ns();
    my_query(m, "START TRANSACTION", "mysql begin");
    for (int64_t i = 0; i < rows; i++) {
        const char *name = NAMES[i % 16];
        mysql_real_escape_string(m, escaped, name, (unsigned long)strlen(name));
        snprintf(q, sizeof q, "INSERT INTO bench VALUES (%lld, '%s', %.17ge0)", (long long)i, escaped, (double)i * 0.5);
        my_query(m, q, "mysql insert");
    }
    my_query(m, "COMMIT", "mysql commit");
    int64_t insert_ns = now_ns() - t0;

    t0 = now_ns();
    my_query(m, "SELECT id, name, score FROM bench", "mysql scan");
    MYSQL_RES *res = mysql_use_result(m);
    MYSQL_ROW row;
    int64_t count = 0, sum = 0, bytes = 0;
    while ((row = mysql_fetch_row(res)) != NULL) {
        unsigned long *lengths = mysql_fetch_lengths(res);
        sum += strtoll(row[0], NULL, 10);
        bytes += (int64_t)lengths[1];
        volatile double score = strtod(row[2], NULL);
        (void)score;
        count++;
    }
    mysql_free_result(res);
    int64_t scan_ns = now_ns() - t0;
    if (count != rows || sum != rows * (rows - 1) / 2) die("mysql scan");

    t0 = now_ns();
    int64_t found = 0;
    for (int64_t j = 0; j < lookups; j++) {
        snprintf(q, sizeof q, "SELECT name, score FROM bench WHERE id = %lld", (long long)((j * 7919) % rows));
        my_query(m, q, "mysql lookup");
        res = mysql_use_result(m);
        if ((row = mysql_fetch_row(res)) != NULL) found++;
        while (mysql_fetch_row(res) != NULL) {}
        mysql_free_result(res);
        /* The driver asks for further results after each one, as multi-statement mode requires. */
        while (mysql_next_result(m) == 0) {}
    }
    int64_t lookup_ns = now_ns() - t0;
    if (found != lookups) die("mysql lookup");
    mysql_close(m);
    printf("mysql insert_ns=%lld scan_ns=%lld lookup_ns=%lld\n", (long long)insert_ns, (long long)scan_ns, (long long)lookup_ns);
}

/* ---- odbc */
/* ASCII to UTF-16, as the Neper driver converts every text it sends. */
static SQLWCHAR *wide(const char *s, SQLWCHAR *out, size_t cap) {
    size_t i = 0;
    for (; s[i] && i + 1 < cap; i++) out[i] = (SQLWCHAR)(unsigned char)s[i];
    out[i] = 0;
    return out;
}

static void odbc_ok(SQLRETURN rc, SQLSMALLINT kind, SQLHANDLE h, const char *what) {
    if (SQL_SUCCEEDED(rc)) return;
    SQLCHAR state[6] = { 0 }, message[512] = { 0 };
    SQLINTEGER native = 0;
    SQLSMALLINT length = 0;
    SQLGetDiagRecA(kind, h, 1, state, &native, message, sizeof message, &length);
    fprintf(stderr, "%s %s\n", state, message);
    die(what);
}

static void odbc_direct(SQLHDBC dbc, const char *sql, const char *what) {
    SQLHSTMT st;
    SQLWCHAR text[256];
    odbc_ok(SQLAllocHandle(SQL_HANDLE_STMT, dbc, &st), SQL_HANDLE_DBC, dbc, what);
    odbc_ok(SQLExecDirectW(st, wide(sql, text, 256), SQL_NTS), SQL_HANDLE_STMT, st, what);
    SQLFreeHandle(SQL_HANDLE_STMT, st);
}

static void run_odbc(const char *connection, int64_t rows, int64_t lookups) {
    SQLHENV env;
    SQLHDBC dbc;
    SQLHSTMT st;
    SQLWCHAR text[512];
    SQLAllocHandle(SQL_HANDLE_ENV, SQL_NULL_HANDLE, &env);
    SQLSetEnvAttr(env, SQL_ATTR_ODBC_VERSION, (SQLPOINTER)SQL_OV_ODBC3, 0);
    SQLAllocHandle(SQL_HANDLE_DBC, env, &dbc);
    odbc_ok(SQLDriverConnectW(dbc, NULL, wide(connection, text, 512), SQL_NTS, NULL, 0, NULL, SQL_DRIVER_NOPROMPT), SQL_HANDLE_DBC, dbc, "odbc connect");
    odbc_direct(dbc, "DROP TABLE IF EXISTS bench", "odbc drop");
    odbc_direct(dbc, "CREATE TABLE bench(id BIGINT PRIMARY KEY, name VARCHAR(32) NOT NULL, score DOUBLE PRECISION NOT NULL)", "odbc create");

    int64_t t0 = now_ns();
    SQLSetConnectAttr(dbc, SQL_ATTR_AUTOCOMMIT, (SQLPOINTER)SQL_AUTOCOMMIT_OFF, 0);
    SQLAllocHandle(SQL_HANDLE_STMT, dbc, &st);
    odbc_ok(SQLPrepareW(st, wide("INSERT INTO bench VALUES (?, ?, ?)", text, 512), SQL_NTS), SQL_HANDLE_STMT, st, "odbc prepare");
    SQLBIGINT id;
    SQLWCHAR name[32];
    SQLLEN name_length;
    double score;
    SQLLEN id_length = 0, score_length = 0;
    for (int64_t i = 0; i < rows; i++) {
        id = i;
        wide(NAMES[i % 16], name, 32);
        name_length = (SQLLEN)(strlen(NAMES[i % 16]) * sizeof(SQLWCHAR));
        score = (double)i * 0.5;
        SQLBindParameter(st, 1, SQL_PARAM_INPUT, SQL_C_SBIGINT, SQL_BIGINT, 0, 0, &id, 0, &id_length);
        SQLBindParameter(st, 2, SQL_PARAM_INPUT, SQL_C_WCHAR, SQL_WVARCHAR, 32, 0, name, sizeof name, &name_length);
        SQLBindParameter(st, 3, SQL_PARAM_INPUT, SQL_C_DOUBLE, SQL_DOUBLE, 0, 0, &score, 0, &score_length);
        odbc_ok(SQLExecute(st), SQL_HANDLE_STMT, st, "odbc insert");
    }
    SQLFreeHandle(SQL_HANDLE_STMT, st);
    odbc_ok(SQLEndTran(SQL_HANDLE_DBC, dbc, SQL_COMMIT), SQL_HANDLE_DBC, dbc, "odbc commit");
    SQLSetConnectAttr(dbc, SQL_ATTR_AUTOCOMMIT, (SQLPOINTER)SQL_AUTOCOMMIT_ON, 0);
    int64_t insert_ns = now_ns() - t0;

    t0 = now_ns();
    SQLAllocHandle(SQL_HANDLE_STMT, dbc, &st);
    odbc_ok(SQLExecDirectW(st, wide("SELECT id, name, score FROM bench", text, 512), SQL_NTS), SQL_HANDLE_STMT, st, "odbc scan");
    int64_t count = 0, sum = 0, bytes = 0;
    SQLLEN length;
    while (SQL_SUCCEEDED(SQLFetch(st))) {
        SQLGetData(st, 1, SQL_C_SBIGINT, &id, 0, &length);
        SQLGetData(st, 2, SQL_C_WCHAR, name, sizeof name, &length);
        SQLGetData(st, 3, SQL_C_DOUBLE, &score, 0, &length);
        sum += id;
        bytes += length;
        count++;
    }
    SQLFreeHandle(SQL_HANDLE_STMT, st);
    int64_t scan_ns = now_ns() - t0;
    if (count != rows || sum != rows * (rows - 1) / 2) die("odbc scan");

    t0 = now_ns();
    SQLAllocHandle(SQL_HANDLE_STMT, dbc, &st);
    odbc_ok(SQLPrepareW(st, wide("SELECT name, score FROM bench WHERE id = ?", text, 512), SQL_NTS), SQL_HANDLE_STMT, st, "odbc prepare select");
    int64_t found = 0;
    for (int64_t j = 0; j < lookups; j++) {
        id = (j * 7919) % rows;
        SQLBindParameter(st, 1, SQL_PARAM_INPUT, SQL_C_SBIGINT, SQL_BIGINT, 0, 0, &id, 0, &id_length);
        odbc_ok(SQLExecute(st), SQL_HANDLE_STMT, st, "odbc lookup");
        if (SQL_SUCCEEDED(SQLFetch(st))) {
            SQLGetData(st, 1, SQL_C_WCHAR, name, sizeof name, &length);
            SQLGetData(st, 2, SQL_C_DOUBLE, &score, 0, &length);
            found++;
        }
        SQLCloseCursor(st);
    }
    SQLFreeHandle(SQL_HANDLE_STMT, st);
    int64_t lookup_ns = now_ns() - t0;
    if (found != lookups) die("odbc lookup");
    SQLDisconnect(dbc);
    SQLFreeHandle(SQL_HANDLE_DBC, dbc);
    SQLFreeHandle(SQL_HANDLE_ENV, env);
    printf("odbc insert_ns=%lld scan_ns=%lld lookup_ns=%lld\n", (long long)insert_ns, (long long)scan_ns, (long long)lookup_ns);
}

int main(int argc, char **argv) {
    if (argc < 5) die("usage: bench-c sqlite|postgresql|mysql|odbc <location> <rows> <lookups>");
    int64_t rows = atoll(argv[3]), lookups = atoll(argv[4]);
    if (!strcmp(argv[1], "sqlite")) run_sqlite(argv[2], rows, lookups);
    else if (!strcmp(argv[1], "postgresql")) run_postgresql(argv[2], rows, lookups);
    else if (!strcmp(argv[1], "odbc")) run_odbc(argv[2], rows, lookups);
    else run_mysql((unsigned)atoi(argv[2]), rows, lookups);
    return 0;
}
