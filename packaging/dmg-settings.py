"""Finder layout for the BendMac drag-to-install disk image."""
import os

application = defines['app']
files = [application]
symlinks = {'Applications': '/Applications'}
volume_icon = os.path.join(application, 'Contents', 'Resources', 'AppIcon.icns')
background = defines['background']
format = 'UDZO'
window_rect = ((200, 140), (660, 420))
icon_locations = {'BendMac.app': (180, 212), 'Applications': (480, 212)}
icon_size = 80
text_size = 13
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
include_list_view_settings = False
default_view = 'icon-view'
arrange_by = None
