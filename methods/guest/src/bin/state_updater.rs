#![no_main]

use core::panic;
use std::io::Read;

use alloy_primitives::{Address, FixedBytes, U256, Uint};
use alloy_sol_types::{sol, SolType};
use risc0_zkvm::guest::env;
use tiny_keccak::{Hasher, Keccak};

risc0_zkvm::guest::entry!(main);

fn hash(values: Vec<u8>) -> [u8; 32] {
    let mut digest = [0u8; 32];
    let mut hasher = Keccak::v256();
    for i in 0..values.len() {
        hasher.update(&[values[i]]);
    }
    hasher.finalize(&mut digest);
    digest
}

fn hash_state(state: &State) -> FixedBytes<32> {
    FixedBytes::from(hash(State::encode(state)))
}

sol! {
    #[derive(Debug)]
    struct Position {
        address user;
        uint256 collateral;
        uint256 borrowed;
    }

    #[derive(Debug)]
    struct State {
        address collateralAsset;
        address borrowAsset;
        uint256 collateralAssetPrice;
        uint256 borrowAssetPrice;
        uint256 maxLTV;
        uint256 minCollateralizationRatio;
        uint256 positionsLength;
        // TODO: replace with root hash of trie structure
        Position[] positions;
    }

    #[derive(Debug)]
    struct ActionData {
        uint256 action;
        address user;
        uint256 amount;
    }

    #[derive(Debug)]
    struct Payload {
        ActionData actionData;
        bytes32 stateAccumulator;
        State state;
        bytes signature;
    }

    #[derive(Debug)]
    struct AssetTransfer {
        address asset;
        address from;
        address to;
        uint256 amount;
    }

    #[derive(Debug)]
    struct Response {
        bytes32 prevStateAccumulator;
        bytes32 stateAccumulator;
        AssetTransfer[] assetTransfers;
        ActionData actionData;
        bytes signature;
    }
}

fn check_collateralization_ratio(
    collateral: Uint<256, 4>,
    borrowed: Uint<256, 4>,
    min_collateralization_ratio: Uint<256, 4>,
    collateral_asset_price: Uint<256, 4>,
    borrow_asset_price: Uint<256, 4>
) -> Option<()> {
    let wad = Uint::from(10).pow(Uint::from(18));

    let collateral_value = collateral
        .checked_mul(collateral_asset_price).unwrap()
        .checked_div(wad).unwrap();
    let borrowed_value = borrowed
        .checked_mul(borrow_asset_price).unwrap()
        .checked_div(wad).unwrap();

    if borrowed_value == Uint::from(0) {
        return Some(());
    }

    let collateralization_ratio = collateral_value
        .checked_mul(Uint::from(100)).unwrap()
        .checked_mul(wad).unwrap()
        .checked_div(borrowed_value).unwrap();
    
    if collateralization_ratio >= min_collateralization_ratio {
        return Some(());
    }

    panic!("Collateralization ratio too low: {:?}, {:?}", collateralization_ratio.to_string(), min_collateralization_ratio.to_string());
    
}

fn main() {
    let mut input_bytes = Vec::<u8>::new();
    env::stdin().read_to_end(&mut input_bytes).unwrap();
    let mut decoded = Payload::decode(&input_bytes, true).unwrap();
    assert_eq!(decoded.stateAccumulator, hash_state(&decoded.state));

    let index = match decoded
        .state
        .positions
        .iter()
        .position(|p| p.user == decoded.actionData.user)
    {
        Some(index) => index,
        None => {
            decoded.state.positions.push(Position {
                user: decoded.actionData.user,
                collateral: U256::from(0),
                borrowed: U256::from(0),
            });
            decoded.state.positions.len() - 1
        }
    };

    let mut asset_transfers = Vec::<AssetTransfer>::new();

    match decoded.actionData.action.to_string().as_str() {
        // Deposit
        "0" => {
            decoded.state.positions[index].collateral = decoded.state.positions[index]
                .collateral
                .checked_add(decoded.actionData.amount)
                .unwrap();
            asset_transfers.push(AssetTransfer {
                asset: decoded.state.collateralAsset,
                from: decoded.actionData.user,
                to: Address::ZERO,
                amount: decoded.actionData.amount,
            });
        }
        // Withdraw
        "1" => {
            decoded.state.positions[index].collateral = decoded.state.positions[index]
                .collateral
                .checked_sub(decoded.actionData.amount)
                .unwrap();
            asset_transfers.push(AssetTransfer {
                asset: decoded.state.collateralAsset,
                from: Address::ZERO,
                to: decoded.actionData.user,
                amount: decoded.actionData.amount,
            });
        }
        // Borrow
        "2" => {
            decoded.state.positions[index].borrowed = decoded.state.positions[index]
                .borrowed
                .checked_add(decoded.actionData.amount)
                .unwrap();
            asset_transfers.push(AssetTransfer {
                asset: decoded.state.borrowAsset,
                from: Address::ZERO,
                to: decoded.actionData.user,
                amount: decoded.actionData.amount,
            });
        }
        // Repay
        "3" => {
            decoded.state.positions[index].borrowed = decoded.state.positions[index]
                .borrowed
                .checked_sub(decoded.actionData.amount)
                .unwrap();
            asset_transfers.push(AssetTransfer {
                asset: decoded.state.borrowAsset,
                from: decoded.actionData.user,
                to: Address::ZERO,
                amount: decoded.actionData.amount,
            });
        }
        _ => {
            panic!("Invalid action");
        }
    };

    check_collateralization_ratio(
        decoded.state.positions[index].collateral,
        decoded.state.positions[index].borrowed,
        decoded.state.minCollateralizationRatio,
        decoded.state.collateralAssetPrice,
        decoded.state.borrowAssetPrice,
    );

    env::commit_slice(&Response::encode(&Response {
        prevStateAccumulator: decoded.stateAccumulator,
        stateAccumulator: hash_state(&decoded.state),
        assetTransfers: asset_transfers,
        actionData: decoded.actionData,
        signature: decoded.signature,
    }));
}
