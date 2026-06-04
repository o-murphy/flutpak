# Generated file — do not edit.
# This file is included from CMakeLists.txt and lists plugins.

set(FLUTTER_PLUGIN_LIST
)

set(FLUTTER_FFI_PLUGIN_LIST
)

set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CMAKE_CURRENT_SOURCE_DIR}/../plugins/")

foreach(plugin ${FLUTTER_PLUGIN_LIST})
  add_subdirectory(${plugin}/linux plugins/${plugin})
  target_link_libraries(${BINARY_NAME} PRIVATE ${plugin}_plugin)
endforeach(plugin)

foreach(ffi_plugin ${FLUTTER_FFI_PLUGIN_LIST})
  add_subdirectory(${ffi_plugin}/linux plugins/${ffi_plugin})
endforeach(ffi_plugin)
