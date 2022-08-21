#!/usr/bin/env bash

butler push bundle/windows/ desttinghim/punch-em-up:windows   --userversion $1
butler push bundle/linux/ desttinghim/punch-em-up:linux       --userversion $1
butler push bundle/mac/ desttinghim/punch-em-up:mac           --userversion $1
butler push bundle/html/ desttinghim/punch-em-up:html         --userversion $1
butler push bundle/cart/ desttinghim/punch-em-up:cart         --userversion $1
