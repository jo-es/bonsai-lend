// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {IBonsaiRelay} from "bonsai/IBonsaiRelay.sol";
import {BonsaiLowLevelCallbackReceiver} from "bonsai/BonsaiLowLevelCallbackReceiver.sol";

import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract Entrypoint is BonsaiLowLevelCallbackReceiver {
    using ECDSA for bytes32;

    uint64 public constant BONSAI_CALLBACK_GAS_LIMIT = 100000;
    bytes32 public immutable imageId;
    address public immutable owner;

    bytes32 public stateAccumulator;

    struct ActionData {
        uint256 action;
        address user;
        uint256 amount;
    }

    struct AssetTransfer {
        address asset;
        address from;
        address to;
        uint256 amount;
    }

    struct Response {
        bytes32 prevStateAccumulator;
        bytes32 nextStateAccumulator;
        AssetTransfer[] assetTransfers;
        ActionData actionData;
        bytes signature;
    }

    event UpdateStateCallback(bytes32 indexed prevStateAccumulator, bytes32 indexed nextStateAccumulator);

    constructor(IBonsaiRelay bonsaiRelay, bytes32 imageId_) BonsaiLowLevelCallbackReceiver(bonsaiRelay) {
        imageId = imageId_;
        owner = msg.sender;
    }

    modifier onlyImageId(bytes32 imageId_) {
        require(imageId_ == imageId, "callback does not come from the expected imageId");
        _;
    }

    function setInitialStateAccumulator(bytes32 initialStateAccumulator) external {
        require(msg.sender == owner, "only owner can set initial state accumulator");
        require(stateAccumulator == bytes32(0), "initial state accumulator already set");
        stateAccumulator = initialStateAccumulator;
    }

    function bonsaiLowLevelCallback(bytes calldata journal, bytes32 imageId_)
        internal
        override
        onlyImageId(imageId_)
        returns (bytes memory)
    {
        Response memory response = abi.decode(journal, (Response));

        require(response.prevStateAccumulator == stateAccumulator, "invalid prev. state accumulator");
        stateAccumulator = response.nextStateAccumulator;
        emit UpdateStateCallback(stateAccumulator, response.nextStateAccumulator);

        bytes32 signedHash = keccak256(abi.encode((response.actionData))).toEthSignedMessageHash();
        require(signedHash.recover(response.signature) == response.actionData.user, "invalid signature");

        for (uint256 i = 0; i < response.assetTransfers.length; i++) {
            AssetTransfer memory assetTransfer = response.assetTransfers[i];
            if (assetTransfer.asset != address(0)) {
                if (assetTransfer.from == address(0)) {
                    IERC20(assetTransfer.asset).transfer(assetTransfer.to, assetTransfer.amount);
                } else if (assetTransfer.to == address(0)) {
                    IERC20(assetTransfer.asset).transferFrom(assetTransfer.from, address(this), assetTransfer.amount);
                }
            }
        }

        return new bytes(0);
    }
}
