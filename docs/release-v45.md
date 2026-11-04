# SOSBROO 0.10.14+45 — Android offline public mesh room

## Supported Android architecture

Nearby Connections P2P_CLUSTER discovers and connects phones without an Internet
connection or an infrastructure hotspot. The app implements multi-hop routing.
Nearby selects the underlying radio; Wi-Fi-only operation is not guaranteed.
Stock Android does not expose Wi-Fi IBSS to ordinary apps. This release does
not claim IBSS support. Google Play services, permissions, and functioning local
radios are required; users need a previously cached account for offline startup.

Official references:
- https://developers.google.com/nearby/connections/overview
- https://developer.android.com/develop/connectivity/wifi/wifi-direct

## Public disaster room

Open Messages → ห้องสนทนาส่วนกลาง. All participating upgraded devices receive
public text, replies, edits, retracts and deletes through relays. Every device
persists signed events; late joiners receive history including tombstones.
Periodic inventories request missing events after dropped broadcasts. The room
works independently of Supabase both when Internet is present and absent.
This is a public nearby room, not a worldwide cloud group. Existing private
image/video/location chat remains separate; public-room attachments are not
implemented in this release. Never copy private conversation rows into this room.

Events carry a self-signed device certificate and signature verified using the
existing pinned mesh keys. This proves device authorship, not a verified member
or rescuer identity. Only the author can mutate their own messages. Deletes hide
content in the room; signed history/tombstones remain stored for convergence.

## Connection corrections

The previous native incoming-direction filter could reject a sole incoming
RFCOMM connection. Direction arbitration now applies only to duplicate sockets;
replacement readers cannot remove a newer socket. Keepalive bypasses the bulk
receive queue, a single failed ping no longer tears down a link, and the silence
deadline is 60 seconds. Native close callbacks still remove broken links promptly.

## Physical acceptance test still required

Install v45 on every phone. Disable mobile data and disconnect all infrastructure
Wi-Fi; leave Wi-Fi/Bluetooth radios and Android location enabled. Use three phones
A—B—C with A and C unable to connect directly. Send a public message from each
phone; all three must display it once. Edit/retract/delete, disconnect a phone,
send while isolated, reconnect and verify history converges. Repeat after locking
screens and switching the relay. Simulated tests do not certify physical radio
stability, range, throughput, or vendor battery management.
