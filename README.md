# Punch'em Up

A tiny beat'em up for the [WASM-4](https://wasm4.org) fantasy console.

## Building

Build the cart by running:

```shell
zig build -Drelease-small opt
```

Then run it with:

```shell
w4 run zig-out/lib/cart.wasm
```

For more info about setting up WASM-4, see the [quickstart guide](https://wasm4.org/docs/getting-started/setup?code-lang=zig#quickstart).
