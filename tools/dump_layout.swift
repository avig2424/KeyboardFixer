// Throwaway generator: dumps the authoritative US <-> Hebrew character mapping
// by querying the actual macOS keyboard layouts via UCKeyTranslate.
//
// Run:  swift tools/dump_layout.swift
import Carbon
import Foundation

func layoutData(for sourceID: String) -> CFData? {
    let props = [kTISPropertyInputSourceID as String: sourceID] as CFDictionary
    guard let list = TISCreateInputSourceList(props, true)?.takeRetainedValue() as? [TISInputSource],
          let src = list.first else { return nil }
    guard let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return nil }
    return Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue()
}

func listHebrewSources() -> [String] {
    guard let list = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] else { return [] }
    var ids: [String] = []
    for src in list {
        if let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) {
            let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
            if id.lowercased().contains("hebrew") { ids.append(id) }
        }
    }
    return ids
}

func char(_ data: CFData, keyCode: UInt16, shift: Bool) -> String? {
    let layoutPtr = unsafeBitCast(CFDataGetBytePtr(data), to: UnsafePointer<UCKeyboardLayout>.self)
    var deadKeyState: UInt32 = 0
    var chars = [UniChar](repeating: 0, count: 8)
    var length = 0
    let modifierKeyState: UInt32 = shift ? UInt32((shiftKey >> 8) & 0xFF) : 0
    let status = UCKeyTranslate(
        layoutPtr,
        keyCode,
        UInt16(kUCKeyActionDown),
        modifierKeyState,
        UInt32(LMGetKbdType()),
        OptionBits(kUCKeyTranslateNoDeadKeysBit),
        &deadKeyState,
        chars.count,
        &length,
        &chars)
    if status != noErr || length == 0 { return nil }
    return String(utf16CodeUnits: chars, count: length)
}

print("Installed Hebrew layouts: \(listHebrewSources())\n")

// US (ABC) layout. "com.apple.keylayout.US" or "ABC".
let usData = layoutData(for: "com.apple.keylayout.US") ?? layoutData(for: "com.apple.keylayout.ABC")
let heData = layoutData(for: "com.apple.keylayout.Hebrew")

guard let us = usData else { fatalError("No US layout found") }
guard let he = heData else { fatalError("No Hebrew layout found") }

// Virtual key codes for the main typing block (number row, three letter rows).
let keyCodes: [UInt16] = Array(0...53)

func u(_ s: String) -> String { s.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ") }

print("keyCode | shift | US -> HE   (US scalars / HE scalars)")
for kc in keyCodes {
    for shift in [false, true] {
        guard let usc = char(us, keyCode: kc, shift: shift),
              let hec = char(he, keyCode: kc, shift: shift) else { continue }
        if usc == hec { continue } // identical in both layouts -> not a "mistake" case
        print("\(kc)\t\(shift ? "S" : " ")\t'\(usc)' -> '\(hec)'\t(\(u(usc)) / \(u(hec)))")
    }
}
