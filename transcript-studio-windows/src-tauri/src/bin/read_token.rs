use keyring::Entry;

fn main() {
    let entry = Entry::new("nl.prezent.transcript-studio", "auth_token")
        .expect("Failed to create keyring entry");
    match entry.get_password() {
        Ok(token) => println!("{}", token),
        Err(e) => eprintln!("No token found: {}", e),
    }
}
