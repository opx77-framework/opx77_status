# opx77_status

> [!WARNING]
> **This project is currently in early development and is not considered production-ready.**
>
> The API, architecture, features, and internal systems are subject to change at any time without prior notice. Breaking changes may be introduced as development progresses.
>
> **Do not rely on the current API for production resources yet.**

A shared status-effect strip for **Opx77**. Any resource adds a chip — bleeding, over encumbered, a wanted level, a buff on a timer — and this one owns the surface, the ordering and the countdown.

Without it every resource that wanted to say something on screen would draw its own box, and they would overlap.

## Features

- Chips with a label, a tone, a priority and an optional countdown
- Effects sorted by priority, so the urgent one is never pushed off by the trivial one
- An effect belongs to the resource that added it, and goes when that resource stops
- Stopping this resource takes the strip down with it, instead of leaving its chips on screen
- Countdowns run on the page, so a ticking timer costs no traffic

## Exports

| Export | Does |
|---|---|
| `add` | add or replace one of your effects |
| `update` | patch a field of one |
| `remove` | take one down |
| `clear` | take all of yours down |

## Configuration

`config.lua`. Where the strip sits, how many chips are drawn before it collapses into a counter, and the tone palette.

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
