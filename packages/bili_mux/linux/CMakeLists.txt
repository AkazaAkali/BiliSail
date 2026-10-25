cmake_minimum_required(VERSION 3.13)
project(bili_mux LANGUAGES CXX)
if(NOT CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64|AMD64)$")
  message(FATAL_ERROR "bili_mux currently packages Linux x64 only")
endif()
set(MUX_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../native/prebuilt/linux-x64")
if(NOT EXISTS "${MUX_DIR}/libbili_mux.so")
  message(FATAL_ERROR "Build the mux component first: bash packages/bili_mux/tool/build.sh linux-x64 (from the repository root)")
endif()
set(bili_mux_bundled_libraries "${MUX_DIR}/libbili_mux.so"
  "${MUX_DIR}/COPYING.LGPLv2.1" "${MUX_DIR}/source.txt"
  "${MUX_DIR}/configure.log" PARENT_SCOPE)
