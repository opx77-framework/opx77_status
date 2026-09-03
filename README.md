# opx77_status

> [!WARNING]
> **This project is currently in early development and is not considered production-ready.**
>
> The API, architecture, features, and internal systems are subject to change at any time without prior notice. Breaking changes may be introduced as development progresses.
>
> **Do not rely on the current API for production resources yet.**

A shared status-effect strip and the character's gameplay needs, for **Opx77**. Any resource adds a chip — bleeding, over encumbered, a wanted level, a buff on a timer — and this one owns the surface, the ordering and the countdown. It also owns `hunger`, `thirst`, `stamina` and `streetCred`, in its own table, and serves them to `opx77_hud`.

> [!IMPORTANT]
> **The citizen id and the values arrive from the client and are taken at face value.** There is no ownership proof and no server-side re-derivation: this is the project owner's ruling, not an oversight. Every value is still type-checked and clamped before it reaches a column, and both net events are rate limited.

`health`, `armor`, `isDead` and `inLastStand` are **not** here. They stay in `opx77_core`'s `PlayerData.metadata`, because `OPX.PlaceCharacter` reads the stored health to clamp the respawn and applies armour after it.

## Features

- Chips with a label, a tone, a priority and an optional countdown
- Effects sorted by priority, so the urgent one is never pushed off by the trivial one
- An effect belongs to the resource that added it, and goes when that resource stops
- Stopping this resource takes the strip down with it, instead of leaving its chips on screen
- Countdowns run on the page, so a ticking timer costs no traffic
- Needs loaded per character, decayed on the client, and pushed back on a throttle

## Exports

| Export | Does |
|---|---|
| `addEffect` | add or replace one of your effects |
| `updateEffect` | patch a field of one |
| `removeEffect` | take one down |
| `clearEffects` | take all of yours down |
| `getNeeds` | the character's needs as this client holds them |
| `setNeeds` | set one or more needs outright |
| `addNeeds` | move one or more needs by a delta |

The effect exports name what they act on, so a call site cannot be read as touching the needs.

Every export answers a table carrying `ok`, never raises, and takes its caller from `GetInvokingResource()`. The error codes are listed in `types.lua`.

```lua
CreateThread(function()
  local promise = Open77.exports.call("opx77_status", "getNeeds")
  if not promise then return end
  local result, callError = promise:await()
  if callError or not result.ok then return end
  print(result.values.thirst)
end)
```

## Events

| Event | Raised | Carries |
|---|---|---|
| `opx77:status:effects` | the strip changed | `anchor`, `offset`, `chips`, `hidden` |
| `opx77:status` | one effect expired or was removed | `status`, `owner`, `action`, `label`, `tone`, `data` |
| `opx77:status:needs` | a need moved | `values`, `changed`, `source`, `citizenId`, `ready` |

All three are client-local: a listener needs a plain `AddEventHandler` and no permission. Redraw from `opx77:status:needs` rather than polling `getNeeds`.

## How the needs travel

1. The client hears `opx77:client:onPlayerLoaded` and takes the citizen id from it. On a start mid-session it reads the id from `opx77_core`'s `GetPlayerData` export instead.
2. It sends that id to this resource's server half on `opx77_status:pull`.
3. The server answers `opx77_status:values` with the stored row, or the defaults in `config.lua` when there is none.
4. The client owns the values from there: it decays hunger and thirst, serves them, and raises `opx77:status:needs` on every change.
5. It pushes them back on `opx77_status:push` every `PUSH_MS`, and at once when any need moves `PUSH_DELTA`.
6. The server answers `opx77_status:pushed`. The answer names no push, so the client settles the oldest one still waiting and no later one: a push the server refused — past its rate limit, or malformed — is never counted as stored, and its drift is sent again.
7. The server holds the last push in memory and writes it on `onPlayerDisconnected`, every `AUTOSAVE_MS`, and when a second character is pulled onto the same slot. A client cannot send anything at disconnect, so the throttled push during play is what makes the saved value fresh.

`opx77:client:onPlayerUnloaded` clears everything client-side.

## The schema

`sql/status.sql` holds `opx77_character_status`, keyed on `citizen_id`. `server/main.lua` applies the same statement itself at boot, so an operator never has to run it by hand; the file is the copy they read. There is no foreign key to `opx77_characters`: this resource would then refuse to install until the core had migrated, and load order across resources is not ours to decide.

## Configuration

`config.lua`. Where the strip sits, how many chips are drawn before it collapses into a counter, and every need with its bounds, its value on a new character, its decay rate and the two intervals that govern the write path.

## Locales

There is no `locales/` here and no `LOCALE` in `config.lua`, and that is deliberate: every word on the strip is a chip label the calling resource supplied, so that resource is where it is translated. The only strings this one owns are `Open77.log` lines and the error codes, and neither is translated.

## Community & Support

Join the Open77 and Opx77 communities to discover the platform, share your projects, and connect with other developers.

<!-- TODO: replace with the final URLs before publication. -->

* [Open77](#)
* [Open77 GitHub](#)
* [OPX Discord](#)

## License

opx77_status is licensed under the [**MIT License**](LICENSE).

Copyright © 2026 **Luis MOUTA**.

<p align="center">
    <sub>opx77_status is an independent community project and is not affiliated with or endorsed by CD PROJEKT RED.</sub>
</p>
