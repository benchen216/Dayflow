//
//  AppDataDirectory.swift
//  Dayflow
//
//  Folder under ~/Library/Application Support that holds everything this
//  build writes: the database, recordings, the agent socket, and so on.
//  Dayflow+ keeps its own folder so it can run next to upstream Dayflow
//  without the two sharing one database. tools/dayflow-cli mirrors this name.
//

import Foundation

enum AppDataDirectory {
  static let name = "DayflowPlus"
}
