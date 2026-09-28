//! The e.db benchmark's workload in Rust, with each database's standard synchronous crate:
//! rusqlite (linked to the system SQLite, the library the Neper and C benchmarks use),
//! postgres, mysql, and odbc-api over the host's driver manager.
//!
//!     bench-rust sqlite <file> <rows> <lookups>
//!     bench-rust postgresql <conninfo> <rows> <lookups>
//!     bench-rust mysql <port> <rows> <lookups>
//!     bench-rust odbc <connection string> <rows> <lookups>
//!
//! Same phases, table and output line as benchmarks/db/src/workload.e and c/bench.c.
use std::time::Instant;

const NAMES: [&str; 16] = [
    "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india", "juliett",
    "kilo", "lima", "mike", "november", "oscar", "papa",
];
const CREATE: &str =
    "CREATE TABLE bench(id BIGINT PRIMARY KEY, name VARCHAR(32) NOT NULL, score DOUBLE PRECISION NOT NULL)";

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

fn verify(count: i64, sum: i64, rows: i64, found: i64, lookups: i64) -> Result<()> {
    if count != rows || sum != rows * (rows - 1) / 2 || found != lookups {
        return Err(format!("read {count} rows, found {found} of {lookups}").into());
    }
    Ok(())
}

fn sqlite(path: &str, rows: i64, lookups: i64) -> Result<(u128, u128, u128)> {
    let mut db = rusqlite::Connection::open(path)?;
    db.execute("DROP TABLE IF EXISTS bench", [])?;
    db.execute(CREATE, [])?;

    let t0 = Instant::now();
    let tx = db.transaction()?;
    {
        let mut insert = tx.prepare("INSERT INTO bench VALUES (?, ?, ?)")?;
        for i in 0..rows {
            insert.execute(rusqlite::params![i, NAMES[(i % 16) as usize], i as f64 * 0.5])?;
        }
    }
    tx.commit()?;
    let insert_ns = t0.elapsed().as_nanos();

    let t0 = Instant::now();
    let (mut count, mut sum, mut bytes) = (0i64, 0i64, 0usize);
    {
        let mut scan = db.prepare("SELECT id, name, score FROM bench")?;
        let mut result = scan.query([])?;
        while let Some(row) = result.next()? {
            let id: i64 = row.get(0)?;
            let name: String = row.get(1)?;
            let _score: f64 = row.get(2)?;
            sum += id;
            bytes += name.len();
            count += 1;
        }
    }
    let scan_ns = t0.elapsed().as_nanos();

    let t0 = Instant::now();
    let mut found = 0i64;
    {
        let mut lookup = db.prepare("SELECT name, score FROM bench WHERE id = ?")?;
        for j in 0..lookups {
            let hit: rusqlite::Result<(String, f64)> = lookup.query_row([j * 7919 % rows], |r| Ok((r.get(0)?, r.get(1)?)));
            if hit.is_ok() {
                found += 1;
            }
        }
    }
    let lookup_ns = t0.elapsed().as_nanos();
    let _ = bytes;
    verify(count, sum, rows, found, lookups)?;
    Ok((insert_ns, scan_ns, lookup_ns))
}

fn postgresql(conninfo: &str, rows: i64, lookups: i64) -> Result<(u128, u128, u128)> {
    let mut client = postgres::Client::connect(conninfo, postgres::NoTls)?;
    client.batch_execute("DROP TABLE IF EXISTS bench")?;
    client.batch_execute(CREATE)?;

    let t0 = Instant::now();
    let mut tx = client.transaction()?;
    let insert = tx.prepare("INSERT INTO bench VALUES ($1, $2, $3)")?;
    for i in 0..rows {
        tx.execute(&insert, &[&i, &NAMES[(i % 16) as usize], &(i as f64 * 0.5)])?;
    }
    tx.commit()?;
    let insert_ns = t0.elapsed().as_nanos();

    // query_raw streams: rows are decoded as they arrive, not collected first.
    let t0 = Instant::now();
    let (mut count, mut sum, mut bytes) = (0i64, 0i64, 0usize);
    {
        use postgres::fallible_iterator::FallibleIterator;
        let mut result = client.query_raw("SELECT id, name, score FROM bench", std::iter::empty::<i64>())?;
        while let Some(row) = result.next()? {
            let id: i64 = row.get(0);
            let name: &str = row.get(1);
            let _score: f64 = row.get(2);
            sum += id;
            bytes += name.len();
            count += 1;
        }
    }
    let scan_ns = t0.elapsed().as_nanos();

    let t0 = Instant::now();
    let lookup = client.prepare("SELECT name, score FROM bench WHERE id = $1")?;
    let mut found = 0i64;
    for j in 0..lookups {
        if let Some(row) = client.query_opt(&lookup, &[&(j * 7919 % rows)])? {
            let _name: &str = row.get(0);
            let _score: f64 = row.get(1);
            found += 1;
        }
    }
    let lookup_ns = t0.elapsed().as_nanos();
    let _ = bytes;
    verify(count, sum, rows, found, lookups)?;
    Ok((insert_ns, scan_ns, lookup_ns))
}

fn mysql(port: &str, rows: i64, lookups: i64) -> Result<(u128, u128, u128)> {
    use mysql::prelude::Queryable;
    let options = mysql::OptsBuilder::new()
        .ip_or_hostname(Some("127.0.0.1"))
        .tcp_port(port.parse()?)
        .user(Some("root"))
        .db_name(Some("neper"));
    let mut conn = mysql::Conn::new(options)?;
    conn.query_drop("DROP TABLE IF EXISTS bench")?;
    conn.query_drop(CREATE)?;

    let t0 = Instant::now();
    {
        let mut tx = conn.start_transaction(mysql::TxOpts::default())?;
        let insert = tx.prep("INSERT INTO bench VALUES (?, ?, ?)")?;
        for i in 0..rows {
            tx.exec_drop(&insert, (i, NAMES[(i % 16) as usize], i as f64 * 0.5))?;
        }
        tx.commit()?;
    }
    let insert_ns = t0.elapsed().as_nanos();

    let t0 = Instant::now();
    let (mut count, mut sum, mut bytes) = (0i64, 0i64, 0usize);
    {
        let result = conn.query_iter("SELECT id, name, score FROM bench")?;
        for row in result {
            let (id, name, _score): (i64, String, f64) = mysql::from_row(row?);
            sum += id;
            bytes += name.len();
            count += 1;
        }
    }
    let scan_ns = t0.elapsed().as_nanos();

    let t0 = Instant::now();
    let lookup = conn.prep("SELECT name, score FROM bench WHERE id = ?")?;
    let mut found = 0i64;
    for j in 0..lookups {
        let hit: Option<(String, f64)> = conn.exec_first(&lookup, (j * 7919 % rows,))?;
        if hit.is_some() {
            found += 1;
        }
    }
    let lookup_ns = t0.elapsed().as_nanos();
    let _ = bytes;
    verify(count, sum, rows, found, lookups)?;
    Ok((insert_ns, scan_ns, lookup_ns))
}

// Row by row with get_data, as the Neper driver and the C baseline read: no bound column buffers.
fn odbc(connection: &str, rows: i64, lookups: i64) -> Result<(u128, u128, u128)> {
    use odbc_api::{Connection, ConnectionOptions, Cursor, Environment, IntoParameter};
    let env = Environment::new()?;
    let conn: Connection = env.connect_with_connection_string(connection, ConnectionOptions::default())?;
    conn.execute("DROP TABLE IF EXISTS bench", (), None)?;
    conn.execute(CREATE, (), None)?;

    let t0 = Instant::now();
    conn.set_autocommit(false)?;
    {
        let mut insert = conn.prepare("INSERT INTO bench VALUES (?, ?, ?)")?;
        for i in 0..rows {
            insert.execute((&i, &NAMES[(i % 16) as usize].into_parameter(), &(i as f64 * 0.5)))?;
        }
    }
    conn.commit()?;
    conn.set_autocommit(true)?;
    let insert_ns = t0.elapsed().as_nanos();

    let t0 = Instant::now();
    let (mut count, mut sum, mut bytes) = (0i64, 0i64, 0usize);
    let mut name = Vec::new();
    if let Some(mut cursor) = conn.execute("SELECT id, name, score FROM bench", (), None)? {
        while let Some(mut row) = cursor.next_row()? {
            let (mut id, mut score) = (0i64, 0f64);
            row.get_data(1, &mut id)?;
            row.get_text(2, &mut name)?;
            row.get_data(3, &mut score)?;
            sum += id;
            bytes += name.len();
            count += 1;
        }
    }
    let scan_ns = t0.elapsed().as_nanos();

    let t0 = Instant::now();
    let mut found = 0i64;
    {
        let mut lookup = conn.prepare("SELECT name, score FROM bench WHERE id = ?")?;
        for j in 0..lookups {
            let key = j * 7919 % rows;
            if let Some(mut cursor) = lookup.execute(&key)? {
                if let Some(mut row) = cursor.next_row()? {
                    let mut score = 0f64;
                    row.get_text(1, &mut name)?;
                    row.get_data(2, &mut score)?;
                    found += 1;
                }
            }
        }
    }
    let lookup_ns = t0.elapsed().as_nanos();
    let _ = bytes;
    verify(count, sum, rows, found, lookups)?;
    Ok((insert_ns, scan_ns, lookup_ns))
}

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 5 {
        return Err("usage: bench-rust sqlite|postgresql|mysql|odbc <location> <rows> <lookups>".into());
    }
    let (rows, lookups): (i64, i64) = (args[3].parse()?, args[4].parse()?);
    let (insert_ns, scan_ns, lookup_ns) = match args[1].as_str() {
        "sqlite" => sqlite(&args[2], rows, lookups)?,
        "postgresql" => postgresql(&args[2], rows, lookups)?,
        "odbc" => odbc(&args[2], rows, lookups)?,
        _ => mysql(&args[2], rows, lookups)?,
    };
    println!("{} insert_ns={insert_ns} scan_ns={scan_ns} lookup_ns={lookup_ns}", args[1]);
    Ok(())
}
