import re

def inject_scene(file_path, node_name, node_parent, pos_x, pos_y):
    with open(file_path, 'r', encoding='utf-8') as f:
        text = f.read()

    if 'res://scenes/ui/settings_menu.tscn' in text:
        return

    highest_id_num = 1
    for match in re.finditer(r'\[ext_resource .*?id="(\d+)_?[^"]*?"\]', text):
        highest_id_num = max(highest_id_num, int(match.group(1)))
        
    new_ext_id = f'{highest_id_num + 1}_stngs'
    
    last_ext_idx = text.rfind('[ext_resource')
    if last_ext_idx != -1:
        end_of_ext = text.find('\n', last_ext_idx) + 1
    else:
        end_of_ext = text.find('\n') + 1
        
    ext_str = f'[ext_resource type="PackedScene" uid="uid://bmpyvms5vjv8" path="res://scenes/ui/settings_menu.tscn" id="{new_ext_id}"]\n'
    text = text[:end_of_ext] + ext_str + text[end_of_ext:]
    
    node_str = f'''
[node name="{node_name}" parent="{node_parent}" instance=ExtResource("{new_ext_id}")]
layout_mode = 0
offset_left = {pos_x}.0
offset_top = {pos_y}.0
offset_right = {pos_x + 32}.0
offset_bottom = {pos_y + 32}.0
unique_name_in_owner = true
'''
    text += node_str
    
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(text)

inject_scene('scenes/ui/main_lobby.tscn', 'BtnSettings', '.', 1220, 20)
inject_scene('scenes/ui/login_screen.tscn', 'BtnSettings', '.', 1220, 20)
print('Injected cleanly!')
