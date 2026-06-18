/// Cross-OS key mapping (FR-12).
///
/// ENSI's neutral [InputEvent.keyCode] space **is the Win32 virtual-key code**
/// (so Windows capture/injection is identity). This table maps those neutral
/// codes to/from X11 keysyms for the Linux backend. Table-driven and pure, so it
/// is fully unit-testable without any platform calls.
class KeyMap {
  /// neutral (Win32 VK) -> X11 keysym.
  static final Map<int, int> _vkToKeysym = _build();

  /// X11 keysym -> neutral (Win32 VK).
  static final Map<int, int> _keysymToVk = {
    for (final e in _vkToKeysym.entries) e.value: e.key,
  };

  /// Map a neutral key code to an X11 keysym (null if unmapped).
  static int? vkToKeysym(int vk) => _vkToKeysym[vk];

  /// Map an X11 keysym back to a neutral key code (null if unmapped).
  static int? keysymToVk(int keysym) => _keysymToVk[keysym];

  static Map<int, int> _build() {
    final m = <int, int>{};

    // Letters A-Z: VK 0x41-0x5A <-> lowercase keysym 0x61-0x7A.
    for (var i = 0; i < 26; i++) {
      m[0x41 + i] = 0x61 + i;
    }
    // Digits 0-9: identical code points (0x30-0x39) in both spaces.
    for (var i = 0; i < 10; i++) {
      m[0x30 + i] = 0x30 + i;
    }
    // Function keys F1-F12: VK 0x70-0x7B <-> keysym 0xFFBE-0xFFC9.
    for (var i = 0; i < 12; i++) {
      m[0x70 + i] = 0xFFBE + i;
    }

    // Whitespace / editing.
    m[0x20] = 0x20; //   space
    m[0x0D] = 0xFF0D; // Enter / Return
    m[0x1B] = 0xFF1B; // Escape
    m[0x09] = 0xFF09; // Tab
    m[0x08] = 0xFF08; // Backspace
    m[0x2E] = 0xFFFF; // Delete
    m[0x2D] = 0xFF63; // Insert

    // Navigation.
    m[0x25] = 0xFF51; // Left
    m[0x26] = 0xFF52; // Up
    m[0x27] = 0xFF53; // Right
    m[0x28] = 0xFF54; // Down
    m[0x24] = 0xFF50; // Home
    m[0x23] = 0xFF57; // End
    m[0x21] = 0xFF55; // Page Up (VK_PRIOR)
    m[0x22] = 0xFF56; // Page Down (VK_NEXT)

    // Modifiers (left/right where the hook distinguishes them).
    m[0xA0] = 0xFFE1; // Left Shift
    m[0xA1] = 0xFFE2; // Right Shift
    m[0xA2] = 0xFFE3; // Left Control
    m[0xA3] = 0xFFE4; // Right Control
    m[0xA4] = 0xFFE9; // Left Alt (VK_LMENU)
    m[0xA5] = 0xFFEA; // Right Alt (VK_RMENU)
    m[0x5B] = 0xFFEB; // Left Super / Win
    m[0x5C] = 0xFFEC; // Right Super / Win
    m[0x14] = 0xFFE5; // Caps Lock

    return m;
  }
}
