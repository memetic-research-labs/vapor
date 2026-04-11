# Prompt History

Every time you compress a prompt, Vapor automatically saves both the original and compressed text along with token counts, compression ratio, the backend used, and a timestamp. You can browse, search, filter, and restore past prompts at any time.

## Opening History

Press `⌘ Y` to open the Prompt History window. This works from both the compact pill view and the full editor.

The history window is a separate, independently moveable window. It stays open while you continue working in the main editor.

**Screenshot needed:** `screens/history-window.png` — the prompt history window showing several entries grouped by day.

## What's Saved

Each history entry contains:

| Field | Description |
|---|---|
| Original text | Your full input text before compression |
| Compressed text | The PC-compressed output |
| Original tokens | BPE token count of the original |
| Compressed tokens | BPE token count of the compressed output |
| Compression ratio | compressed / original (lower is better) |
| Compressor used | Which backend was used (Foundation Models, Local LLM, OpenRouter) |
| Timestamp | When the compression was performed |
| Favorite | Whether you've starred this entry |

## Browsing History

### Grouped by Day

Entries are grouped into sections:
- **Today** — prompts from today
- **Yesterday** — prompts from yesterday
- **Date** (e.g., "Apr 8, 2026") — older prompts by date

### Search

Type in the search field at the top to filter by any text in the original or compressed content. The search is case-insensitive and updates in real-time.

### Favorites Filter

Click the star icon (⭐) in the header to show only favorited entries. Click again to show all entries.

## History Card

Each entry shows:

1. **Original text** — first 2 lines, truncated
2. **Compressed text** — first line, monospaced
3. **Stats** — ratio, token counts, compressor used
4. **Time** — formatted as time for today, "Yesterday" + time, or date + time
5. **Star button** — toggle favorite
6. **Delete button** — remove entry (with undo)

**Screenshot needed:** `screens/history-card.png` — close-up of a single history card showing all fields.

## Restoring a Prompt

Click any history card to restore its original text to the editor:

1. If the editor has unsaved content, it's **automatically saved** as a new history entry first
2. The editor is replaced with the restored entry's original text
3. The compressed preview and token counts are also restored
4. A toast confirms: "Restored from history"

This means you never lose work — restoring auto-saves whatever was in the editor.

## Deleting Entries

Click the trash icon on a history card to delete it. An **undo bar** appears at the bottom of the history window for 4 seconds. Click "Undo" to restore the deleted entry.

All history is kept permanently — there is no automatic pruning or limit on the number of entries.

## Storage

Prompt history is stored locally using SwiftData in the app's container. The data stays on your Mac and is not synced to any cloud service.
