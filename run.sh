#!/usr/bin/env bash

cd starfish_original
gleam run &
cd ../starfish_updated
gleam run &
cd ..

# Give time for the servers to start up
sleep 5
gleam run
