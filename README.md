# Bonsai Lend

> **Note: This software is not production ready. Do not use in production.**

This is a proof-of-concept implementation of a simplified lending protocol that encapsulates all app-specific logic as a [RISC Zero](http://risczero.com) [Bonsai](https://dev.risczero.com/bonsai/) [zkVM](https://dev.risczero.com/zkvm/) program. The zkVM program computes the new state of the protocol and all required asset transfers, and only token transfers and the storage of an accumulator of the resulting state (after the ZKP has been successfully verified) are done on-chain. This architecture offloads computationally intensive state transitions and allows for the reuse of the protocol core logic on different domains (even non-EVM domains).

## Dependencies
First, [install Rust](https://doc.rust-lang.org/book/ch01-01-installation.html) and [Foundry](https://github.com/foundry-rs/foundry), and then restart your terminal. Next, you will need to install the `cargo risczero tool`:

```bash
cargo install cargo-risczero
```

For the above commands to build successfully you will need to have installed the required dependencies. 

```bash
sudo apt install curl build-essential libssl-dev pkgconf
```

Next we'll need to install the `risc0` toolchain with:

```bash
cargo risczero install
```

## Quick Start
First, install the RISC Zero toolchain using the instructions above. 

- Use `make test-dev` for running the tests without the Bonsai API

- Use `make test` for running the tests with the Bonsai API

  - Create a `.env` file that contains the Bonsai API credentials:
  - ***Note:*** *To request an API key [complete the form here](https://bonsai.xyz/apply).*
    ```
    export BONSAI_API_KEY=<BONSAI_API_KEY>
    export BONSAI_API_URL=<BONSAI_API_URL>
    ```

