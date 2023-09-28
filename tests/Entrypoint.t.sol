// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.17;

import {BonsaiTest} from "bonsai/BonsaiTest.sol";
import {IBonsaiRelay} from "bonsai/IBonsaiRelay.sol";
import {BonsaiLowLevelCallbackReceiver} from "bonsai/BonsaiLowLevelCallbackReceiver.sol";

import {ERC20PresetMinterPauser} from "openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import {ECDSA} from "openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {Entrypoint} from "contracts/Entrypoint.sol";

contract EntrypointTest is BonsaiTest {
    using ECDSA for bytes32;

    uint256 public constant USER_PRIVATE_KEY = 0xabc123;
    address public immutable USER = vm.addr(USER_PRIVATE_KEY);

    enum Action {
        Deposit,
        Withdraw,
        Borrow,
        Repay
    }

    struct Position {
        address user;
        uint256 collateral;
        uint256 borrowed;
    }

    struct State {
        address collateralAsset;
        address borrowAsset;
        uint256 collateralAssetPrice;
        uint256 borrowAssetPrice;
        uint256 maxLTV;
        uint256 positionsLength;
        // TODO: replace with root hash of trie structure
        Position[] positions;
    }

    struct ActionData {
        uint256 action;
        address user;
        uint256 amount;
    }

    struct Payload {
        ActionData actionData;
        bytes32 stateAccumulator;
        State state;
        bytes signature;
    }

    function setUp() public withRelay {}

    function sign(ActionData memory actionData) internal returns (bytes memory) {
        vm.startPrank(vm.addr(USER_PRIVATE_KEY));
        bytes32 digest = keccak256(abi.encode(actionData)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_PRIVATE_KEY, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.stopPrank();
        return signature;
    }

    function testDeposit() public {
        Entrypoint entrypoint = new Entrypoint(IBonsaiRelay(bonsaiRelay), queryImageId('state_updater'));

        ERC20PresetMinterPauser collateralAsset = new ERC20PresetMinterPauser("Collateral", "COL");
        ERC20PresetMinterPauser borrowAsset = new ERC20PresetMinterPauser("Borrow", "BOR");
        collateralAsset.mint(USER, 1 ether);
        borrowAsset.mint(address(entrypoint), 1 ether);

        vm.startPrank(USER);
        collateralAsset.approve(address(entrypoint), 1 ether);
        vm.stopPrank();

        State memory initialState = State({
            collateralAsset: address(collateralAsset),
            borrowAsset: address(borrowAsset),
            collateralAssetPrice: 1 ether,
            borrowAssetPrice: 1 ether,
            maxLTV: 100 ether,
            positionsLength: 0,
            positions: new Position[](0)
        });

        bytes32 initialStateAccumulator = keccak256(abi.encode(initialState));

        entrypoint.setInitialStateAccumulator(initialStateAccumulator);

        ActionData memory actionData = ActionData(uint256(Action.Deposit), USER, uint256(1 ether));
        bytes memory signature = sign(actionData);

        runCallbackRequest(
            entrypoint.imageId(),
            abi.encode(
                Payload({
                    stateAccumulator: initialStateAccumulator,
                    state: initialState,
                    actionData: actionData,
                    signature: signature
                })
            ),
            address(entrypoint),
            BonsaiLowLevelCallbackReceiver.bonsaiLowLevelCallbackReceiver.selector,
            entrypoint.BONSAI_CALLBACK_GAS_LIMIT()
        );

        State memory stateAfterDeposit = State({
            collateralAsset: address(collateralAsset),
            borrowAsset: address(borrowAsset),
            collateralAssetPrice: 1 ether,
            borrowAssetPrice: 1 ether,
            maxLTV: 100 ether,
            positionsLength: 0,
            positions: new Position[](1)
        });
        stateAfterDeposit.positions[0] = Position(USER, 1 ether, 0);

        bytes32 stateAccumulator = entrypoint.stateAccumulator();
        assertTrue(stateAccumulator != initialStateAccumulator);
        assertTrue(stateAccumulator == keccak256(abi.encode(stateAfterDeposit)));

        actionData = ActionData(uint256(Action.Withdraw), USER, uint256(1 ether));
        signature = sign(actionData);

        runCallbackRequest(
            entrypoint.imageId(),
            abi.encode(
                Payload({
                    stateAccumulator: stateAccumulator,
                    state: stateAfterDeposit,
                    actionData: actionData,
                    signature: signature
                })
            ),
            address(entrypoint),
            BonsaiLowLevelCallbackReceiver.bonsaiLowLevelCallbackReceiver.selector,
            entrypoint.BONSAI_CALLBACK_GAS_LIMIT()
        );

        State memory stateAfterWithdraw = State({
            collateralAsset: address(collateralAsset),
            borrowAsset: address(borrowAsset),
            collateralAssetPrice: 1 ether,
            borrowAssetPrice: 1 ether,
            maxLTV: 100 ether,
            positionsLength: 0,
            positions: new Position[](1)
        });
        stateAfterWithdraw.positions[0] = Position(USER, 0 ether, 0);

        stateAccumulator = entrypoint.stateAccumulator();
        assertTrue(stateAccumulator == keccak256(abi.encode(stateAfterWithdraw)));
    }
}
