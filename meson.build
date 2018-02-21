project('VLC', 'c')

incdir = include_directories('include')

add_global_arguments('-DHAVE_CONFIG_H=1', language : 'c')
cc = meson.get_compiler('c')

subdir('src')
