from kitty.tab_bar import DrawData, ExtraData, TabBarData, draw_tab_with_powerline, as_rgb
from kitty.fast_data_types import Screen


def draw_tab(
    draw_data: DrawData,
    screen: Screen,
    tab: TabBarData,
    before: int,
    max_tab_length: int,
    index: int,
    is_last: bool,
    extra_data: ExtraData,
) -> int:
    end = draw_tab_with_powerline(
        draw_data, screen, tab, before, max_tab_length, index, is_last, extra_data,
    )

    if is_last and tab.active_session_name:
        session_label = f"   {tab.active_session_name}  "
        label_len = len(session_label)
        cells_available = screen.columns - end

        if cells_available >= label_len:
            # Draw right-aligned session indicator
            padding = cells_available - label_len
            screen.cursor.x = end + padding
            screen.cursor.bg = as_rgb(0xAB6C7D)  # gruvbox dim purple
            screen.cursor.fg = as_rgb(0x282828)   # gruvbox bg dark
            screen.cursor.bold = True
            screen.draw(session_label)

    return end
