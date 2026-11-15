//! Independent decoder only; no game library is loaded or executed.
use std::{env, error::Error, fs};

fn main() -> Result<(), Box<dyn Error>> {
    let args: Vec<_> = env::args().collect();
    if args.len() == 2 && args[1] == "--version" {
        println!("zgta-menu-codec 0.1.0 oozextract 0.5.7");
        return Ok(());
    }
    if args.len() != 4 {
        return Err("Expected INPUT OUTPUT EXACT_OUTPUT_BYTES, or --version".into());
    }
    let size: usize = args[3].parse()?;
    if size == 0 || size > 8 * 1024 * 1024 {
        return Err("Menu block output must be between 1 byte and 8 MiB".into());
    }
    let length = fs::metadata(&args[1])?.len();
    if length == 0 || length > 8 * 1024 * 1024 {
        return Err("Menu compressed block must be between 1 byte and 8 MiB".into());
    }
    let input = fs::read(&args[1])?;
    let mut output = vec![0; size];
    let decoded = oozextract::Extractor::new().read_from_slice(&input, &mut output)?;
    if decoded != size {
        return Err(format!("Decoded {decoded} bytes; required exactly {size}").into());
    }
    fs::write(&args[2], output)?;
    Ok(())
}
