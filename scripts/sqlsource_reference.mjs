// Reference vectors for `e.algo.sqlsource` (L037): run appdor's own src/sync/sql-source.js over random single operations --
// the dialect, the operator's host list, host and address verdicts, the connection a URL makes, identifiers and the
// statements built from them, redaction, driver diagnostics and the rows an information schema answers -- and write the
// link fixture tests/selfhost/fixtures/link/algo_sqlsource. APPDOR_DIR defaults to D:/repos/appdor.
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { appdor, canon, clone, emit, rng } from './ref_common.mjs';

const sql = await import(pathToFileURL(resolve(appdor, 'src/sync/sql-source.js')).href);
const { int, pick, chance } = rng(0x5a17);

const HOSTS = ['db.example.com', 'DB.Example.COM.', '10.0.0.7', '[::1]', '[fe80::1]:5432', 'db:5433', 'db:0', 'db:70000', 'db:abc', 'db:', ':5432', 'a b', '*', '**', 'ANY',
  'all', '0.0.0.0', '::', '0.0.0.0/0', '::/0', 'x?y', '*.example.com', '.example.com', 'host/16', 'https://db', 'user@db', 'db.internal:5432', '[::1', '[]', '[::1]:', 'fe80::1',
  '2001:db8::1', 'localhost', 'a"b', "a'b", 'db:5432:1', 'DB:5432'];
const genHostList = () => Array.from({ length: int(5) }, () => pick(HOSTS)).join(pick([',', ' ', ', ', ',,  ', '\n']));

const ADDRESSES = ['127.0.0.1', '127.1.2.3', '0.0.0.0', '0.1.2.3', '169.254.169.254', '::1', '::', '::ffff:127.0.0.1', '::ffff:7f00:1', '::FFFF:7F00:0001', '::ffff:10.0.0.1',
  '::ffff:a00:1', '[::1]', '10.0.0.7', '8.8.8.8', '', '  ', 'db.example.com', '2001:db8::1', '::ffff:169.254.169.254', '::ffff:a9fe:a9fe', '::ffff:0.0.0.1', '1.127.0.0.1', 'fe80::1.'];

const genEntries = () => {
  const parsed = sql.parseSqlSourceHosts(Array.from({ length: int(4) }, () => pick(['db.example.com', 'db:5433', '10.0.0.7', '127.0.0.1', '::1', '[::ffff:7f00:1]', 'a.b:5432'])).join(','));
  return parsed.ok ? parsed.entries : [];
};

const URLS = ['postgres://db.example.com/app', 'postgresql://db.example.com:5433/app?sslmode=disable', 'POSTGRES://DB.Example.com/app', 'postgres://user@db/app', 'postgres://user:pw@db/app',
  'postgres://:@db/app', 'postgres://@db/app', 'postgres://db/app?sslmode=verify-full', 'postgres://db/app?sslmode=no-verify', 'postgres://db/app?sslmode=prefer', 'postgres://db/app?sslmode=',
  'postgres://db/app?sslmode=REQUIRE', 'postgres://db/app?x=1&sslmode=disable', 'postgres://db/app?sslmode=a%20b', 'postgres://db:0/app', 'postgres://db:65536/app', 'postgres://db:65535/app',
  'postgres://db:5432/', 'postgres://db', 'postgres://db/', 'postgres://db/a%20b', 'postgres://db/a%2Fb', 'postgres://db/' + 'x'.repeat(63), 'postgres://db/' + 'x'.repeat(64),
  'postgres://[::1]:5432/app', 'postgres://[::1]/app', 'postgres:///app', 'postgres:db/app', 'mysql://db/app', 'http://db/app', '', 'postgres://db:abc/app', 'postgres://db/app#frag',
  'postgres://db/a%zz', 'postgres://a b/app', 'postgres://db/app?sslmode=disable#x', 'postgres://db:/app', 'postgres://db:05432/app', 'postgres://db/ap%00p'];
const AUTHS = [undefined, null, {}, { username: 'u', password: 'p' }, { user: 'u2' }, { username: '', user: 'alt', password: 'x' }, { password: 'only' }, { username: 5 }];

const IDENTS = ['orders', '_x', 'a$b', '1abc', 'a-b', '', 'x'.repeat(63), 'x'.repeat(64), 'public', 'Mixed_Case', 'a b', 'é', 'a"b'];
const ENTITIES = ['orders', 'public.orders', 'public/orders', '/public/orders/', 'a.b.c', 'a/b/c', '', '   ', '.', 'a.', '.b', 'a..b', '1x.t', 's.t u', 'order$1', '//x//', ' sales.items ', 'a/b.c'];

const SECRETS = ['hunter2', 'pw', 'p', '', 'abc', 'x y', '***', 'db.example.com'];
const TEXTS = ['connect postgres://u:hunter2@db.example.com/app failed', 'password=hunter2 rejected', 'PASSWORD = "p a s s" bad', "pgpassword='x y'", 'passfile=/home/u/.pgpass ok',
  'no secrets here', 'mypassword=keep', 'postgres://user@db/app', 'x-y://a:b@h and https://c:d@e', 'password="unterminated', 'password=', 'password:hunter2', 'http://a:b:c@h/p',
  'ftp://u:pw@h password=pw2 end', '1abc://u:p@h', 'user:hunter2@db', 'sql-source-row-cap-exceeded:12', 'SSL connection has been closed', 'server does not support SSL', 'Connection TIMEOUT',
  'it timed out', 'password=\'a b\' tail', 'xpassword=1 password=2', 'postgres://u:p@h/db?password=zz'];
const CODES = ['28P01', '28000', 28000, '42501', '42P01', '3D000', '3F000', '57014', 57014, '53300', '25006', 'ECONNREFUSED', 'ENOTFOUND', 'EAI_AGAIN', 'ETIMEDOUT', 'ECONNRESET',
  'EHOSTUNREACH', 'ENETUNREACH', 'CERT_HAS_EXPIRED', 'DEPTH_ZERO_SELF_SIGNED_CERT', 'SELF_SIGNED_CERT_IN_CHAIN', 'ERR_TLS_CERT_ALTNAME_INVALID', 'XX000', '', undefined, null, 0];

const CELLS = [null, true, false, 0, 1, -2.5, 'text', '', { a: 1, b: [1, 2] }, [1, 'x', null], {}, []];
const genRow = () => Object.fromEntries(['id', 'name', 'meta', 'tags', 'n'].filter(() => chance(0.7)).map((k) => [k, pick(CELLS)]));
const NAMES = ['public', 'sales', 'x', '', null, 0, undefined];

function genOp() {
  switch (int(20)) {
    case 0: return { op: 'dialect', url: pick([...URLS, 'POSTGRESQL://x', 'redis://x', 'postgres', ':', 'p1://x', 'a+b.c-d:x']) };
    case 1: return { op: 'channel', channel: pick([{ baseUrl: 'postgres://h/db' }, { baseUrl: 'mysql://h' }, {}, null, { baseUrl: '' }, { baseUrl: 5 }, undefined]) };
    case 2: case 3: return { op: 'hosts', raw: pick([genHostList(), genHostList(), '', undefined, null, 'db.example.com,db.example.com,db:5432,db:5432']) };
    case 4: return { op: 'host', host: pick(['db.example.com', 'DB.EXAMPLE.COM.', '[::1]', '', '  ', '10.0.0.7', 'other', 'db']), port: pick([5432, 5433, '5433', 0, undefined, 70000]), entries: pick([genEntries(), [], undefined, genEntries()]) };
    case 5: case 6: return { op: 'address', address: pick(ADDRESSES), entries: pick([genEntries(), [], undefined]) };
    case 7: case 8: case 9: return { op: 'source', baseUrl: pick(URLS), auth: pick(AUTHS) };
    case 10: return { op: 'ident', name: pick(IDENTS) };
    case 11: return { op: 'entity', entity: pick(ENTITIES) };
    case 12: return { op: 'statements', limit: pick([undefined, 1, 10, 499, 500, 501, 0, -5, 2.5, '7', 'x', null, 600000, 500000, 499999]), schema: pick(IDENTS), table: pick(IDENTS) };
    case 13: return { op: 'session', timeout: pick([undefined, 0, 500, 1000, 5000, 15000, 600000, 700000, '2000', 'x', null]) };
    case 14: case 15: return { op: 'redact', text: pick(TEXTS), secrets: Array.from({ length: int(3) }, () => pick(SECRETS)) };
    case 16: return { op: 'diag', error: pick([{ code: pick(CODES), message: pick(TEXTS) }, { message: pick(TEXTS) }, { code: pick(CODES) }, null, undefined, {}, { message: 'x'.repeat(450) }, { code: pick(CODES), message: 'no match' }]), secrets: Array.from({ length: int(3) }, () => pick(SECRETS)) };
    case 17: return { op: pick(['value', 'row']), value: pick(CELLS), row: pick([genRow(), null, {}]) };
    case 18: return { op: 'bytes', data: Array.from({ length: int(6) }, () => int(256)) };
    default: return pick([
      { op: 'entities', rows: Array.from({ length: int(6) }, () => pick([{ table_schema: pick(NAMES), table_name: pick(NAMES) }, { tableSchema: 'a', tableName: 'b' }, null, {}, { table_schema: 'a', tableSchema: 'z', table_name: 't' }])) },
      { op: 'many', n: 520 },
      { op: 'columns', rows: Array.from({ length: int(6) }, () => pick([{ column_name: pick(NAMES), data_type: pick(['TEXT', 'Integer', '', null, undefined, 'timestamp WITH time zone']) }, { columnName: 'c', dataType: 'VARCHAR' }, null, {}, { column_name: 'a', columnName: 'z' }])) },
    ]);
  }
}

const tryReason = (fn) => { try { return fn(); } catch (e) { return { threw: String(e.message) }; } };

function execute(op) {
  switch (op.op) {
    case 'dialect': return { dialect: sql.sqlDialect(op.url) };
    case 'channel': return { sql: sql.isSqlChannel(clone(op.channel)) };
    case 'hosts': return sql.parseSqlSourceHosts(op.raw);
    case 'host': return sql.checkSqlHost(op.host, op.port, clone(op.entries));
    case 'address': return sql.checkSqlAddress(op.address, clone(op.entries));
    case 'source': return sql.sqlSourceFrom({ baseUrl: op.baseUrl, auth: clone(op.auth) });
    case 'ident': return { valid: sql.isValidSqlIdentifier(op.name), quoted: tryReason(() => sql.quoteSqlIdentifier(op.name)) };
    case 'entity': return sql.parseSqlEntity(op.entity);
    case 'statements': return {
      browse: sql.browseTablesStatement(op.limit),
      columns: sql.columnsStatement(op.schema, op.table),
      select: tryReason(() => sql.selectRowsStatement(op.schema, op.table, op.limit)),
      selectDefault: tryReason(() => sql.selectRowsStatement(op.schema, op.table)),
    };
    case 'session': return sql.readOnlySessionStatements(op.timeout);
    case 'redact': return { text: sql.redactSqlText(op.text, op.secrets) };
    case 'diag': return sql.sqlDiagnostic(clone(op.error), op.secrets);
    case 'value': return { value: sql.normalizeSqlValue(clone(op.value)) };
    case 'row': return sql.normalizeSqlRow(clone(op.row));
    case 'bytes': return { value: sql.normalizeSqlValue(Uint8Array.from(op.data)) };
    case 'entities': return sql.sqlEntities(clone(op.rows));
    case 'many': return { count: sql.sqlEntities(Array.from({ length: op.n }, (_, i) => ({ table_schema: 's', table_name: 't' + i }))).length };
    case 'columns': return sql.sqlColumns(clone(op.rows));
    default: throw new Error(op.op);
  }
}

const cases = [];
const kinds = {};
for (let i = 0; i < 900; i++) {
  const op = genOp();
  let expected;
  try { expected = canon(execute(op)); } catch (e) { i -= 1; continue; }
  kinds[op.op] = (kinds[op.op] || 0) + 1;
  cases.push({ op, e: expected });
}
const chunks = emit('algo_sqlsource', 'sqlsource_fixture_template.e', cases, 'algo sqlsource ok');
console.log(`${cases.length} cases in ${chunks} chunks -> algo_sqlsource`, kinds);
