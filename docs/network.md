# The Aurora secure network

Every Aurora computer with a modem can talk to every other one that shares its
**network key**. Chat, the little internet and defense alerts all ride on the
same encrypted transport.

## Setting it up

1. Put a modem on each computer (wireless reaches 64 blocks; an ender modem
   reaches anywhere, across dimensions).
2. On each one: **Settings → Network → Network key**, and type the same
   passphrase.
3. Check the **fingerprint** matches on both. It is derived from the key, so
   two machines showing `D7BEEF78` share a key without either ever displaying
   it.

That is the whole setup. Computers announce themselves every 30 seconds and
find each other automatically.

## What is on the wire

```
{ v = 1, from = 7, name = "base", to = 12, ts = 1738... ,
  nonce = "9f2c1a44bd07",
  body  = "<hex ciphertext>",
  mac   = "<16 hex characters>" }
```

`body` decrypts to a serialised `{ kind = "chat", data = {...} }`.

- **Encryption** is XXTEA with a 128-bit key derived from your passphrase.
- **Authentication** is the same cipher in CBC-MAC form over the version,
  sender, recipient, timestamp, nonce and ciphertext. A frame whose MAC does
  not verify is dropped before anything tries to decrypt it.
- **Replay protection** is the nonce: the last 256 are remembered and a repeat
  is rejected.

### What this does and does not give you

It means somebody sniffing your channel with a modem sees hex, and cannot forge
a message that passes the MAC or replay one they captured earlier.

It does **not** protect you from anyone who can read `/aurora/etc/net.cfg` off
your computer's disk — the key is stored there in the clear, because the
computer has to be able to boot unattended. Treat the network key like a base
password: it keeps out people on the outside, not people already inside.

Changing the key immediately stops traffic encrypted with the old one from
being readable.

## Message kinds

| Kind | Sent by | Meaning |
| --- | --- | --- |
| `net.hello` | every computer, every 30s | "I am here" |
| `net.here` | the reply | "so am I" |
| `chat` | Messages | a chat message |
| `web.who` | Web | "who is hosting?" |
| `web.site` | the web service | "I am, and I am called X" |
| `web.get` / `web.page` | Web | fetch a page and its reply |
| `defense.alert` | Defense | an alarm fired somewhere |

## Using it from your own app

```lua
local net = arequire("svc.net")

-- receive: frames of this kind arrive as an "aurora_net" event
net.subscribe("mygame.move", aurora.pid)

app.onEvent = function(name, kind, sender, data, senderName)
  if name == "aurora_net" and kind == "mygame.move" then
    -- already decrypted, verified and de-duplicated
  end
end

-- send
net.send(12, "mygame.move", { x = 3, y = 9 })
net.broadcast("mygame.hello", {})

-- ask and wait for an answer (blocks only your window)
local reply, err = net.request(12, "mygame.state", {}, "mygame.stateReply", 3)

-- who is out there
for _, peer in ipairs(net.peerList()) do
  print(peer.id, peer.name, peer.online)
end
```

## Hosting a site

The web service serves `/home/www/*.page` to anyone on your network key.
Turn it off in the Web app's menu if you would rather not.

The markup is deliberately small:

```
# Heading
## Subheading
* a bullet
> a quote
---
[Label](12/shop)     link to page "shop" on computer 12
[Label](about)       link to another page on this site
plain text           a paragraph, wrapped to the window
```

## Defense alerts

When a sensor trips on an armed system, Defense broadcasts:

```lua
net.broadcast("defense.alert", { reason = "Front gate tripped",
                                 from = "Main base", clock = "21:14" })
```

Every other computer running Aurora logs it and raises a notification, so one
screen in your house can watch every outpost. Turn it off per-computer in the
Defense menu.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| Status says "no modem" | Nothing of type `modem` is attached. |
| Status says "offline" | A modem exists but would not open. |
| Peers never appear | Different network keys — compare fingerprints. |
| Messages send but never arrive | Out of modem range, or the other computer is off. |
| "bad signature" in the kernel log | Something is transmitting with a different key. |

The System Monitor's Log tab shows what the network service is doing.
