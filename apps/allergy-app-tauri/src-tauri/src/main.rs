// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod ml;
fn main() {
    allergy_app_tauri_lib::run()
}
