mod error;
mod migrate;
mod modulesrc;
mod naming;

use error::Result;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 4 {
        eprintln!("usage: migrate_reference MODE FILE PROJECT");
        std::process::exit(2);
    }
    let mode = args[1].as_str();
    let source = match std::fs::read_to_string(&args[2]) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("error: reading {}: {e}", args[2]);
            std::process::exit(1);
        }
    };
    let project = args[3].as_str();
    let migrated: Result<migrate::Migration> = match mode {
        "ansible" => migrate::migrate_ansible(&source, project),
        "salt" => migrate::migrate_salt(&source, project),
        "puppet" => migrate::migrate_puppet(&source, project),
        "chef" => migrate::migrate_chef(&source, project),
        other => {
            eprintln!("error: unknown mode {other}");
            std::process::exit(2);
        }
    };
    match migrated {
        Ok(m) => {
            println!("migrated: {}", m.migrated);
            for w in &m.warnings {
                println!("warning: {w}");
            }
            println!("---");
            print!("{}", m.yaml);
        }
        Err(e) => {
            eprintln!("error: {e}");
            std::process::exit(1);
        }
    }
}
