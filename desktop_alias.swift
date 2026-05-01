#!/usr/bin/env swift
// 创建一个真正的 macOS Finder Alias 文件（保留原 App 的 logo）
// 用法：swift desktop_alias.swift <target-app-path> <alias-output-path>
// 与 symlink 不同，bookmarkData(.suitableForBookmarkFile) 写出的是 Finder 识别的 alias，
// Finder 会自动显示原 App 的图标，双击会跳到目标 .app 启动。
import Foundation

guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write(Data("用法: swift desktop_alias.swift <target> <alias>\n".utf8))
    exit(1)
}

let target = URL(fileURLWithPath: CommandLine.arguments[1])
let aliasURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard FileManager.default.fileExists(atPath: target.path) else {
    FileHandle.standardError.write(Data("✗ target 不存在: \(target.path)\n".utf8))
    exit(1)
}

try? FileManager.default.removeItem(at: aliasURL)

do {
    let bookmark = try target.bookmarkData(
        options: [.suitableForBookmarkFile],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
    )
    try URL.writeBookmarkData(bookmark, to: aliasURL)
    print("✓ alias 已创建: \(aliasURL.path)")
} catch {
    FileHandle.standardError.write(Data("✗ 失败: \(error)\n".utf8))
    exit(1)
}
