#!/bin/bash

song_info=$(playerctl metadata --format '   {{title}}')

echo "$song_info" 
