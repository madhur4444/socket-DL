// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Socket.sol";
import "../src/interfaces/IAccumulator.sol";

contract SocketTest is Test {
    address constant _owner = address(1);
    uint256 constant _signerPrivateKey = uint256(2);
    address constant _accum = address(3);
    address constant _root = address(4);
    uint256 constant _batchId = uint256(5);
    address _signer;

    uint256 constant _minBondAmount = 100e18;
    uint256 constant _bondClaimDelay = 1 weeks;
    uint256 constant _chainId = 0x2013AA263;

    Socket _socket;

    address constant _signer_1 = address(3);

    function setUp() external {
        _signer = vm.addr(_signerPrivateKey);
        hoax(_owner);
        _socket = new Socket(_minBondAmount, _bondClaimDelay, _chainId);
    }

    function testDeployment() external {
        assertEq(_socket.owner(), _owner);
        assertEq(_socket.minBondAmount(), _minBondAmount);
        assertEq(_socket.bondClaimDelay(), _bondClaimDelay);
        assertEq(_socket.chainId(), _chainId);
    }

    function testAddBond() external {
        uint256 amount = 100e18;
        hoax(_signer);
        _socket.addBond{value: amount}();
        assertEq(_socket.getBond(_signer), amount);
    }

    function testReduceValidAmount() external {
        uint256 initialAmount = 150e18;
        uint256 reduceAmount = 10e18;

        assertGe(initialAmount - reduceAmount, _minBondAmount);

        startHoax(_signer, initialAmount);
        _socket.addBond{value: initialAmount}();
        _socket.reduceBond(reduceAmount);

        assertEq(_socket.getBond(_signer), initialAmount - reduceAmount);
        assertEq(_signer.balance, reduceAmount);
    }

    function testReduceInvalidAmount() external {
        uint256 initialAmount = 150e18;
        uint256 reduceAmount = 90e18;

        assertLt(initialAmount - reduceAmount, _minBondAmount);

        startHoax(_signer, initialAmount);
        _socket.addBond{value: initialAmount}();
        vm.expectRevert(ISocket.InvalidBondReduce.selector);
        _socket.reduceBond(reduceAmount);
    }

    function testUnbondSigner() external {
        uint256 amount = 150e18;
        uint256 claimTime = block.timestamp + _bondClaimDelay;

        startHoax(_signer, amount);
        _socket.addBond{value: amount}();
        _socket.unbondSigner();

        assertEq(_socket.getBond(_signer), 0);
        (uint256 unbondAmount, uint256 unbondClaimTime) = _socket.getUnbondData(
            _signer
        );
        assertEq(unbondAmount, amount);
        assertEq(unbondClaimTime, claimTime);
    }

    function testClaimBondBeforeDelay() external {
        uint256 amount = 150e18;
        uint256 claimTime = block.timestamp + _bondClaimDelay;

        startHoax(_signer, amount);
        _socket.addBond{value: amount}();
        _socket.unbondSigner();

        vm.warp(claimTime - 10);
        vm.expectRevert(ISocket.ClaimTimeLeft.selector);
        _socket.claimBond();

        assertEq(_socket.getBond(_signer), 0);
        (uint256 unbondAmount, uint256 unbondClaimTime) = _socket.getUnbondData(
            _signer
        );
        assertEq(unbondAmount, amount);
        assertEq(unbondClaimTime, claimTime);
        assertEq(_signer.balance, 0);
    }

    function testClaimBondAfterDelay() external {
        uint256 amount = 150e18;
        uint256 claimTime = block.timestamp + _bondClaimDelay;

        startHoax(_signer, amount);
        _socket.addBond{value: amount}();
        _socket.unbondSigner();

        vm.warp(claimTime + 10);
        _socket.claimBond();

        assertEq(_socket.getBond(_signer), 0);
        (uint256 unbondAmount, uint256 unbondClaimTime) = _socket.getUnbondData(
            _signer
        );
        assertEq(unbondAmount, 0);
        assertEq(unbondClaimTime, 0);
        assertEq(_signer.balance, amount);
    }

    function testSubmitSignature() external {
        startHoax(_signer);
        _socket.addBond{value: _minBondAmount}();

        vm.mockCall(
            _accum,
            abi.encodeWithSelector(IAccumulator.sealBatch.selector),
            abi.encode(_root, _batchId)
        );

        bytes32 digest = keccak256(
            abi.encode(_chainId, _accum, _batchId, _root)
        );
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(
            _signerPrivateKey,
            digest
        );

        _socket.submitSignature(sigV, sigR, sigS, _accum);
    }

    function testSubmitSignatureWithoutEnoughBond() external {
        startHoax(_signer);
        _socket.addBond{value: _minBondAmount / 2}();

        vm.mockCall(
            _accum,
            abi.encodeWithSelector(IAccumulator.sealBatch.selector),
            abi.encode(_root, _batchId)
        );

        bytes32 digest = keccak256(
            abi.encode(_chainId, _accum, _batchId, _root)
        );
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(
            _signerPrivateKey,
            digest
        );

        vm.expectRevert(ISocket.InvalidBond.selector);
        _socket.submitSignature(sigV, sigR, sigS, _accum);
    }
}
