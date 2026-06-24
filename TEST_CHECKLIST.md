# Web Editor Regression Test Checklist

Run these tests on a real device after any changes to `TipTapEditorView.swift`.

## 1. Slash Menu Tests

### Basic Slash Commands
- [ ] Type `/` at start of empty line → menu appears
- [ ] Type `/` in middle of text → menu appears
- [ ] Type `/h1` → filter shows "标题 1"
- [ ] Press Enter on filtered item → format applied, `/h1` deleted
- [ ] Click menu item → format applied, slash text deleted
- [ ] Press Escape → menu closes, `/` remains
- [ ] Press Backspace to delete `/` → menu closes

### Slash Command Format Application
- [ ] `/h1` + Enter → creates H1 heading
- [ ] `/h2` + Enter → creates H2 heading  
- [ ] `/h3` + Enter → creates H3 heading
- [ ] `/bullet` or `/list` + Enter → creates bullet list
- [ ] `/num` or `/ordered` + Enter → creates numbered list
- [ ] `/todo` or `/task` + Enter → creates checkbox item
- [ ] `/quote` + Enter → creates blockquote
- [ ] `/code` + Enter → creates code block
- [ ] `/hr` or `/divider` + Enter → inserts horizontal rule

## 2. Toolbar Format Commands

### Inline Formatting
- [ ] Select text → tap Bold → text becomes **bold**
- [ ] Select text → tap Italic → text becomes *italic*
- [ ] Select text → tap Code → text becomes `code`
- [ ] Select text → tap Strikethrough → text becomes ~~strikethrough~~

### Block Formatting
- [ ] Cursor in paragraph → tap H1 → paragraph becomes heading
- [ ] Cursor in paragraph → tap Bullet → line becomes bullet item
- [ ] Cursor in paragraph → tap Numbered → line becomes numbered item
- [ ] Tap 待办 → inserts task checkbox

## 3. Markdown Shortcuts (Space-triggered)

- [ ] Type `# ` at line start → becomes H1
- [ ] Type `## ` at line start → becomes H2
- [ ] Type `### ` at line start → becomes H3
- [ ] Type `- ` at line start → becomes bullet item
- [ ] Type `* ` at line start → becomes bullet item
- [ ] Type `1. ` at line start → becomes numbered item
- [ ] Type `> ` at line start → becomes blockquote
- [ ] Type `[] ` at line start → becomes task item

## 4. Selection Sync Tests

- [ ] Tap to place cursor → no selection text reported
- [ ] Double-tap word to select → correct word reported in `selectedText`
- [ ] Drag to select multiple words → correct text reported
- [ ] Selection range (`from`, `to`) matches actual position in content

## 5. Content Round-trip Tests

### Create content, save, reload:
- [ ] **Headings**: H1/H2/H3 preserved after reload
- [ ] **Bold/Italic**: Formatting preserved after reload
- [ ] **Code blocks**: Code content preserved (no extra escaping)
- [ ] **Inline code**: Preserved without corruption
- [ ] **Task lists**: Checked/unchecked state preserved
- [ ] **Bullet lists**: List structure preserved
- [ ] **Numbered lists**: Numbers preserved
- [ ] **Blockquotes**: Quote formatting preserved
- [ ] **Horizontal rules**: `---` preserved

### Special Characters:
- [ ] Chinese text (中文) preserved
- [ ] Emoji (🎉) preserved  
- [ ] Code with special chars (`<script>`, `&&`, `||`) preserved
- [ ] Markdown in code blocks (e.g., `# heading`) NOT converted

## 6. Attachment Tests

### Image Insertion
- [ ] Tap 📎 → select image → image appears immediately (local cache)
- [ ] Image shows loading state briefly
- [ ] After upload completes, image still visible
- [ ] Close and reopen note → image still visible
- [ ] Tap 📎 → select Live Photo from Photos → still image appears immediately
- [ ] Open Live Photo preview after paired video finishes loading → photo plays motion
- [ ] Tap 📎 → 拍摄 → capture photo/Live Photo → result inserts into note
- [ ] Reopen/sync on another device → still image appears first, motion becomes available after background download

### Attachment Round-trip
- [ ] Insert image → save → reopen → image displays
- [ ] Check markdown contains `![Attachment](userId/uuid.jpg)` format
- [ ] Markdown does NOT contain `data:` URLs
- [ ] Markdown does NOT contain `https://...supabase...` signed URLs
- [ ] Live Photo paired `.live.mov` is not shown as a separate Assets item

## 7. Task List Tests

- [ ] Create task via `/todo` → checkbox appears
- [ ] Click checkbox → toggles checked state
- [ ] Checked task shows strikethrough text
- [ ] Press Enter in task → creates new task below
- [ ] Press Enter in empty task → converts to paragraph
- [ ] Checked state preserved after reload

## 8. Edge Cases

### Empty States
- [ ] Empty editor shows placeholder text
- [ ] Title field shows placeholder
- [ ] Enter in title → moves focus to editor

### Rapid Typing
- [ ] Fast typing doesn't lose characters
- [ ] Content syncs correctly after rapid edits

### Network Issues
- [ ] Image insertion works offline (shows local cache)
- [ ] Content editing works offline
- [ ] Sync recovers when network returns

## 9. Performance

- [ ] Large note (1000+ lines) scrolls smoothly
- [ ] Slash menu opens quickly (<100ms)
- [ ] Format commands apply instantly
- [ ] No visible lag during typing

---

## Test Results

| Test Area | Pass | Fail | Notes |
|-----------|------|------|-------|
| Slash Menu | | | |
| Toolbar | | | |
| Shortcuts | | | |
| Selection | | | |
| Round-trip | | | |
| Attachments | | | |
| Task Lists | | | |
| Edge Cases | | | |
| Performance | | | |

**Tested on:** [Device/iOS version]  
**Date:** [YYYY-MM-DD]  
**Tester:** [Name]
