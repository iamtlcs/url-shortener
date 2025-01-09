#!/bin/bash

data_to_inject=$1

# Update the HTML file with the data
sed -i "s|{{API_ENDPOINT}}|${data_to_inject}|g" index.html