# Keyboard Bindings Reference

This document lists all keyboard bindings in Majesty, organized by context.

## Global Keys

| Key | Action | Notes |
|-----|--------|-------|
| `Escape` | Close current modal/menu | Works in all contexts |
| `Tab` | Toggle Character Sheet | Opens/closes the party character sheet |

## Crawl Phase (Exploration)

| Key | Action | Notes |
|-----|--------|-------|
| `` ` `` (backtick) | Cycle equipment PC | Switches which PC's hands/belt is shown |
| `Space` | Skip typewriter | Completes the typewriter text animation |
| `X` | Exit dungeon | Only works at entrance room |
| Drag item to POI | Use item | Drag from hands/belt onto clickable text |

## Character Sheet (when open)

| Key | Action | Notes |
|-----|--------|-------|
| `Tab` | Close sheet | Also: `Escape` |
| `1-4` | Select PC | Switches which PC's details are shown |
| Click+drag | Move items | Drag items between hands/belt/pack |

## Loot Modal (when open)

| Key | Action | Notes |
|-----|--------|-------|
| `Escape` | Close modal | Leaves remaining loot in container |
| `1-4` | Select recipient | Switches which PC receives looted items |
| Click | Take item | Click on item to take it |

## Combat Phase

### Command Selection
| Key | Action | Notes |
|-----|--------|-------|
| `1-4` | Select PC | Chooses which PC to give a command |
| `Escape` | Cancel | Cancels current selection |

### Zone Selection
| Key | Action | Notes |
|-----|--------|-------|
| `1-3` | Select zone | Chooses movement destination |
| `Escape` | Cancel | Returns to command selection |

### Target Selection
| Key | Action | Notes |
|-----|--------|-------|
| `1-N` | Select target | Chooses attack target |
| `Escape` | Cancel | Returns to previous selection |

### Resolution
| Key | Action | Notes |
|-----|--------|-------|
| `Space` | Confirm | Confirms current action |
| `1-4` | Quick select PC | Alternative to clicking |

## Camp Phase

| Key | Action | Notes |
|-----|--------|-------|
| `Escape` | Exit camp | Returns to crawl phase |

## Debug Keys (Development Only)

| Key | Action | Notes |
|-----|--------|-------|
| `D` | Draw meatgrinder | Draws a card from GM deck |
| `M` | Advance watch | Increments watch counter |
| `F9` | Auto-win combat | Instantly wins current combat (only during combat) |
| `H` | Debug info | Shows debug information |

---

## Key Binding Priority

When multiple systems could handle a key, priority is:
1. Loot Modal (if open)
2. Character Sheet (if open)
3. Minor Action Panel (if open)
4. Command Board (if open)
5. Phase-specific handlers (crawl, combat, camp)
6. Belt Hotbar
7. Global debug keys

## Design Principles

1. **Context-aware number keys**: 1-4 always selects something relevant to current context
2. **Escape always closes**: Any modal or menu can be closed with Escape
3. **Tab for character sheet**: Primary toggle for the detailed party view
4. **Space for confirmation**: Skip animations or confirm selections
