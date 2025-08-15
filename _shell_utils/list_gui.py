#!/usr/bin/env python3

"""
External Integration Guide for list_gui.py

						This script provides a curses-based GUI for selecting items from a hierarchical list.
						It can be integrated into other applications (e.g., Bash scripts) by passing
						input data via a JSON file and receiving selected items via standard output or an output file.

Usage:
    python3 list_gui.py [--input-file <path_to_json>] [--output-file <path_to_output>]

Input Data Format (JSON file specified by --input-file):
    The JSON file should contain a list of dictionaries, where each dictionary represents
    either an 'item' or a 'category'.

    - Item:
        {'type': 'item', 'name': 'Item Name'}

    - Category:
        {'type': 'category', 'name': 'Category Name', 'children': [...]}
        Categories can be nested.

Example JSON Input (input.json):
    [
        {"type": "category", "name": "Fruits", "children": [
            {"type": "item", "name": "Apple"},
            {"type": "item", "name": "Banana"}
        ]},
        {"type": "item", "name": "Carrot"}
    ]

Output:
    Selected items will be printed one per line to standard output by default.
    If --output-file is specified, selected items will be written to that file, one per line.

Example Integration in Bash:
    #!/bin/bash

    # Create a temporary input JSON file
    cat << EOF > /tmp/input.json
    [
        {"type": "category", "name": "Tasks", "children": [
            {"type": "item", "name": "Task A"},
            {"type": "item", "name": "Task B"}
        ]},
        {"type": "item", "name": "Misc Item"}
    ]
    EOF

    # Run the Python script and capture output
    selected_items=$(python3 /path/to/list_gui.py --input-file /tmp/input.json)

    # Or, write to a file
    # python3 /path/to/list_gui.py --input-file /tmp/input.json --output-file /tmp/selected_items.txt
    # selected_items=$(cat /tmp/selected_items.txt)

    echo "Selected items:"
    echo "$selected_items"

    # Clean up temporary file
    rm /tmp/input.json
"""

import curses

# --- Constants ---
HEADER_OFFSET = 5
FOOTER_HEIGHT = 2 # For scroll indicator or other messages
CHECKBOX_WIDTH = 4 # "[x] " or "[+] "
INDENT_SIZE = 2 # Spaces per level of indentation
PADDING = 2 # Padding around item name

# Color Pairs
COLOR_HIGHLIGHT = 1
COLOR_TITLE = 2
COLOR_INSTRUCTIONS = 3
COLOR_CATEGORY = 4
COLOR_ITEM = 5
COLOR_KEY_NAME = 6

# Helper function to flatten the nested item structure into a list of visible items
def get_visible_items(items_data, level=0):
    visible_list = []
    for item in items_data:
        item['level'] = level # Store level for indentation
        visible_list.append(item)
        if item['type'] == 'category' and item.get('expanded', False):
            visible_list.extend(get_visible_items(item['children'], level + 1))
    return visible_list

def run_checkbox_gui(stdscr, items_data):
    curses.curs_set(0)  # Hide cursor
    stdscr.clear()
    stdscr.refresh()

    def init_selection_status(data):
        for item in data:
            if item['type'] == 'item':
                item['selected'] = False
            elif item['type'] == 'category':
                item['expanded'] = False # All categories start collapsed
                init_selection_status(item['children'])
    init_selection_status(items_data)

    visible_items = get_visible_items(items_data)

    current_row_idx = 0
    top_item_idx = 0
    show_legend = True
    message = ""

    all_names = []
    def collect_names(data):
        for item in data:
            all_names.append(item['name'])
            if item['type'] == 'category':
                collect_names(item['children'])
    collect_names(items_data)

    max_item_len = max(len(name) for name in all_names) if all_names else 0
    item_display_width = CHECKBOX_WIDTH + max_item_len + PADDING

    # Define color pairs
    curses.init_pair(COLOR_HIGHLIGHT, curses.COLOR_BLACK, curses.COLOR_WHITE)
    curses.init_pair(COLOR_TITLE, curses.COLOR_CYAN, curses.COLOR_BLACK)
    curses.init_pair(COLOR_INSTRUCTIONS, curses.COLOR_YELLOW, curses.COLOR_BLACK)
    curses.init_pair(COLOR_CATEGORY, curses.COLOR_BLUE, curses.COLOR_BLACK)
    curses.init_pair(COLOR_ITEM, curses.COLOR_WHITE, curses.COLOR_BLACK)
    curses.init_pair(COLOR_KEY_NAME, curses.COLOR_GREEN, curses.COLOR_BLACK)

    def print_menu(stdscr, selected_row_idx, top_item_idx, item_display_width, h, w, max_rows_per_column, num_columns, show_legend, message=""):
        stdscr.clear()

        # Header
        title = "--- Python Ncurses Checkbox Example ---"
        stdscr.addstr(0, (w - len(title)) // 2, title, curses.color_pair(COLOR_TITLE) | curses.A_BOLD)

        if show_legend:
            stdscr.addstr(2, 0, "Use ", curses.color_pair(COLOR_INSTRUCTIONS))
            stdscr.addstr("UP/DOWN/LEFT/RIGHT", curses.color_pair(COLOR_KEY_NAME))
            stdscr.addstr(" arrows to navigate, ", curses.color_pair(COLOR_INSTRUCTIONS))
            stdscr.addstr("SPACE", curses.color_pair(COLOR_KEY_NAME))
            stdscr.addstr(" to toggle, ", curses.color_pair(COLOR_INSTRUCTIONS))
            stdscr.addstr("ENTER", curses.color_pair(COLOR_KEY_NAME))
            stdscr.addstr(" to confirm (if items selected).", curses.color_pair(COLOR_INSTRUCTIONS))
            stdscr.addstr(3, 0, "Press ", curses.color_pair(COLOR_INSTRUCTIONS))
            stdscr.addstr("h", curses.color_pair(COLOR_KEY_NAME))
            stdscr.addstr(" to toggle legend, ", curses.color_pair(COLOR_INSTRUCTIONS))
            stdscr.addstr("a", curses.color_pair(COLOR_KEY_NAME))
            stdscr.addstr(" to toggle all, ", curses.color_pair(COLOR_INSTRUCTIONS))
            stdscr.addstr("Esc", curses.color_pair(COLOR_KEY_NAME))
            stdscr.addstr(" to abort.", curses.color_pair(COLOR_INSTRUCTIONS))
            stdscr.addstr(4, 0, "-----------------------------------------------------------------", curses.color_pair(COLOR_INSTRUCTIONS))
        else:
            stdscr.addstr(2, 0, "Press ", curses.color_pair(COLOR_INSTRUCTIONS))
            stdscr.addstr("h", curses.color_pair(COLOR_KEY_NAME))
            stdscr.addstr(" for help.", curses.color_pair(COLOR_INSTRUCTIONS))
            stdscr.addstr(3, 0, "", curses.color_pair(COLOR_INSTRUCTIONS)) # Clear line 3
            stdscr.addstr(4, 0, "", curses.color_pair(COLOR_INSTRUCTIONS)) # Clear line 4

        # Display items
        start_row_for_items = HEADER_OFFSET if show_legend else 3 # Adjust based on legend visibility
        for i in range(max_rows_per_column * num_columns):
            current_display_item_idx = top_item_idx + i

            if current_display_item_idx >= len(visible_items):
                break

            item_obj = visible_items[current_display_item_idx]

            row_in_display = i % max_rows_per_column
            col_in_display = i // max_rows_per_column

            x = PADDING + (col_in_display * item_display_width) + (item_obj['level'] * INDENT_SIZE)
            y = row_in_display + start_row_for_items

            checkbox_char = ""
            if item_obj['type'] == 'item':
                checkbox_char = "[x]" if item_obj['selected'] else "[ ]"
            elif item_obj['type'] == 'category':
                checkbox_char = "[-]" if item_obj['expanded'] else "[+]"

            display_string = f"{checkbox_char} {item_obj['name']}"

            if len(display_string) >= item_display_width:
                display_string = display_string[:item_display_width - 1]

            attr = curses.color_pair(COLOR_ITEM)
            if item_obj['type'] == 'category':
                attr = curses.color_pair(COLOR_CATEGORY) | curses.A_BOLD

            if current_display_item_idx == selected_row_idx:
                attr = curses.color_pair(COLOR_HIGHLIGHT)
                if item_obj['type'] == 'category':
                    attr |= curses.A_BOLD

            stdscr.addstr(y, x, display_string, attr)

        # Footer
        if len(visible_items) > (max_rows_per_column * num_columns):
            stdscr.addstr(h - 1, 0, f"Showing {top_item_idx+1}-{min(top_item_idx + (max_rows_per_column * num_columns), len(visible_items))} of {len(visible_items)}")
        
        if message:
            stdscr.addstr(h - 2, 0, message, curses.color_pair(COLOR_INSTRUCTIONS)) # Display message above footer

        stdscr.refresh()

    # Initial dimensions
    h, w = stdscr.getmaxyx()
    max_rows_per_column = h - (HEADER_OFFSET if show_legend else 3) - FOOTER_HEIGHT
    if max_rows_per_column < 1: max_rows_per_column = 1
    num_columns = max(1, (w - PADDING) // item_display_width)

    print_menu(stdscr, current_row_idx, top_item_idx, item_display_width, h, w, max_rows_per_column, num_columns, show_legend, message)

    while True:
        key = stdscr.getch()
        message = "" # Clear message on new key press

        if key == curses.KEY_RESIZE:
            h, w = stdscr.getmaxyx()
            max_rows_per_column = h - (HEADER_OFFSET if show_legend else 3) - FOOTER_HEIGHT
            if max_rows_per_column < 1: max_rows_per_column = 1
            num_columns = max(1, (w - PADDING) // item_display_width)
            # No need to redraw here, it will be redrawn at the end of the loop
        elif key == curses.KEY_UP:
            current_row_idx = max(0, current_row_idx - num_columns)
        elif key == curses.KEY_DOWN:
            current_row_idx = min(len(visible_items) - 1, current_row_idx + num_columns)
        elif key == curses.KEY_LEFT:
            if visible_items[current_row_idx]['type'] == 'category' and visible_items[current_row_idx].get('expanded', False):
                visible_items[current_row_idx]['expanded'] = False
                visible_items = get_visible_items(items_data)
                current_row_idx = min(current_row_idx, len(visible_items) - 1)
            elif num_columns > 1:
                current_row_idx = max(0, current_row_idx - 1)
        elif key == curses.KEY_RIGHT:
            if visible_items[current_row_idx]['type'] == 'category' and not visible_items[current_row_idx].get('expanded', False):
                visible_items[current_row_idx]['expanded'] = True
                visible_items = get_visible_items(items_data)
            elif num_columns > 1:
                current_row_idx = min(len(visible_items) - 1, current_row_idx + 1)
        elif key == curses.KEY_PPAGE:
            page_size = max_rows_per_column * num_columns
            current_row_idx = max(0, current_row_idx - page_size)
        elif key == curses.KEY_NPAGE:
            page_size = max_rows_per_column * num_columns
            current_row_idx = min(len(visible_items) - 1, current_row_idx + page_size)
        elif key == ord(' '):
            if visible_items[current_row_idx]['type'] == 'item':
                visible_items[current_row_idx]['selected'] = not visible_items[current_row_idx]['selected']
        elif key == ord('h'): # Toggle legend
            show_legend = not show_legend
            # Recalculate max_rows_per_column based on new legend visibility
            max_rows_per_column = h - (HEADER_OFFSET if show_legend else 3) - FOOTER_HEIGHT
            if max_rows_per_column < 1: max_rows_per_column = 1
        elif key == ord('a'): # Toggle select all/none
            all_selected = all(item['selected'] for item in visible_items if item['type'] == 'item')
            def set_all_items_selected(data, select_status):
                for item in data:
                    if item['type'] == 'item':
                        item['selected'] = select_status
                    elif item['type'] == 'category':
                        set_all_items_selected(item['children'], select_status)
            set_all_items_selected(items_data, not all_selected)
            visible_items = get_visible_items(items_data) # Re-render with updated selections
        elif key == 27: # ESC key
            return 'aborted by user'
        elif key == curses.KEY_ENTER or key == 10 or key == 13:
            selected_items_count = len([item for item in visible_items if item['type'] == 'item' and item['selected']])
            if selected_items_count > 0:
                break
            else:
                message = "Please select at least one item to confirm." # Set message

        # Adjust top_item_idx to keep current_row_idx visible
        # Calculate the effective row and column of the current_row_idx within the *potential* display area
        effective_row_in_display = (current_row_idx - top_item_idx) % max_rows_per_column
        effective_col_in_display = (current_row_idx - top_item_idx) // max_rows_per_column

        # If current item is above the visible window (vertically)
        if current_row_idx < top_item_idx:
            top_item_idx = current_row_idx
        # If current item is below the visible window (vertically)
        elif effective_row_in_display >= max_rows_per_column:
            top_item_idx = current_row_idx - max_rows_per_column + 1
        # If current item is in a column that is not currently displayed
        elif effective_col_in_display >= num_columns:
            top_item_idx = current_row_idx - (max_rows_per_column * (num_columns - 1))

        # Ensure top_item_idx doesn't go out of bounds
        max_top_item_idx = max(0, len(visible_items) - (max_rows_per_column * num_columns))
        top_item_idx = max(0, min(top_item_idx, max_top_item_idx))

        print_menu(stdscr, current_row_idx, top_item_idx, item_display_width, h, w, max_rows_per_column, num_columns, show_legend, message)

    selected_items = [item['name'] for item in visible_items if item['type'] == 'item' and item['selected']]
    return selected_items

import sys
import json
import argparse

def main():
    parser = argparse.ArgumentParser(description="Multi-item checkbox selection GUI.")
    parser.add_argument("--input-file", type=str,
                        help="Path to a JSON file containing item data.")
    parser.add_argument("--output-file", type=str,
                        help="Path to a file to write selected items to.")
    args = parser.parse_args()

    if args.input_file:
        try:
            with open(args.input_file, 'r') as f:
                input_data = json.load(f)
            all_items = input_data
        except FileNotFoundError:
            print(f"Error: Input file not found at {args.input_file}", file=sys.stderr)
            sys.exit(1)
        except json.JSONDecodeError as e:
            print(f"Error decoding JSON from {args.input_file}: {e}", file=sys.stderr)
            sys.exit(1)
        except Exception as e:
            print(f"An unexpected error occurred reading {args.input_file}: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        # Default example data if no input file is provided
        all_items = [
            {'type': 'category', 'name': 'Category A', 'children': [
                {'type': 'item', 'name': 'Item A1'},
                {'type': 'item', 'name': 'Item A2'},
                {'type': 'category', 'name': 'SubCategory A3', 'children': [
                    {'type': 'item', 'name': 'Item A3.1'},
                    {'type': 'item', 'name': 'Item A3.2'},
                ]},
            ]},
            {'type': 'item', 'name': 'Standalone Item B'},
            {'type': 'category', 'name': 'Category C', 'children': [
                {'type': 'item', 'name': 'Item C1'},
                {'type': 'item', 'name': 'Item C2'},
            ]},
        ]
        # Extend with more items for large list behavior (as in original script)
        for i in range(1, 201):
            all_items.append({'type': 'item', 'name': f"Additional Item {i}"})

    try:
        selected_items = curses.wrapper(run_checkbox_gui, all_items)
        
        if selected_items == 'aborted by user':
            print("Operation aborted by user.", file=sys.stderr)
            sys.exit(1)

        if args.output_file:
            with open(args.output_file, 'w') as f:
                for item in selected_items:
                    f.write(item + '\n')
        else:
            # Fallback to stdout if no output file specified (for direct execution)
            for item in selected_items:
                print(item)
    except Exception as e:
        print(f"An error occurred: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
