# Line icons drawn on a 16×16 grid with stroke: currentColor, so the UI needs no icon font.
# Apps add their own with RuneUi.register_icons.
module RuneUi
  module Icons
    ALL = {
      search: '<circle cx="7" cy="7" r="4"/><path d="m10 10 3 3"/>',
      new: '<path d="M11.5 2.5 13.5 4.5 7 11H5V9z"/><path d="M12 13.5H3.5V5"/>',
      plus: '<path d="M8 3.5v9M3.5 8h9"/>',
      sidebar: '<rect x="2.5" y="3" width="11" height="10" rx="1.5"/><path d="M6.5 3v10"/>',
      copy: '<rect x="5.5" y="5.5" width="7.5" height="7.5" rx="1.5"/><path d="M3 10.5v-6A1.5 1.5 0 0 1 4.5 3h6"/>',
      send: '<path d="M8 13V3M4 7l4-4 4 4"/>',
      chevron: '<path d="m6 4 4 4-4 4"/>',
      back: '<path d="m10 4-4 4 4 4"/>',
      close: '<path d="m4.5 4.5 7 7M11.5 4.5l-7 7"/>',
      check: '<path d="m3.5 8.5 3 3 6-7"/>',
      chat: '<path d="M3 4.5A1.5 1.5 0 0 1 4.5 3h7A1.5 1.5 0 0 1 13 4.5v5A1.5 1.5 0 0 1 11.5 11H7l-3 2.5V11h.5A1.5 1.5 0 0 1 3 9.5z"/>',
      settings: '<circle cx="8" cy="8" r="2"/><path d="M8 2.5v1.5M8 12v1.5M2.5 8H4M12 8h1.5M4.1 4.1l1.06 1.06M10.84 10.84l1.06 1.06M4.1 11.9l1.06-1.06M10.84 5.16l1.06-1.06"/>',
      sign_out: '<path d="M9.5 3H4.5A1.5 1.5 0 0 0 3 4.5v7A1.5 1.5 0 0 0 4.5 13h5"/><path d="M7 8h6.5M11 5.5 13.5 8 11 10.5"/>',
      profile: '<circle cx="8" cy="5.75" r="2.75"/><path d="M3 13.5a5 5 0 0 1 10 0"/>',
      system: '<rect x="2.5" y="3" width="11" height="8" rx="1.5"/><path d="M6 13.5h4M8 11v2.5"/>',
      light: '<circle cx="8" cy="8" r="2.75"/><path d="M8 1.75v1.5M8 12.75v1.5M1.75 8h1.5M12.75 8h1.5M3.6 3.6l1.05 1.05M11.35 11.35l1.05 1.05M3.6 12.4l1.05-1.05M11.35 4.65l1.05-1.05"/>',
      dark: '<path d="M13 9.5A5.5 5.5 0 0 1 6.5 3a5.5 5.5 0 1 0 6.5 6.5z"/>'
    }
  end
end
