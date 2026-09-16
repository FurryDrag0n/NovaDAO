// SPDX-License-Identifier: WTFPL
pragma solidity ^0.8.0;

import "./SmartVault.sol";

// контракт для упрощённого развёртывания множества SmartVault
contract Factory {
    address public immutable asset;
    mapping(address => uint256) public count;
    constructor() {
        // фиксированный адрес
        asset = 0x4613FcB447A1c013Ad86BF097075670C413f991f;
    }
    function init(address reward, uint256 pool, uint24 depositDuration, uint24  stakeDuration) external returns (address) {
        if (reward == address(0))    revert("reward is zero");
        if (pool == 0)               revert("pool is zero");
        if (depositDuration == 0)    revert("deposit duration is zero");
        if (stakeDuration == 0)      revert("stake duration is zero");
        if (reward == asset)         revert("asset == reward");
        uint256 nonce = count[msg.sender];
        bytes32 salt  = keccak256(abi.encodePacked(msg.sender, nonce));
        if (!IERC20(reward).transferFrom(msg.sender, address(this), pool)) revert("reward pull failed");
        address predicted = _predict(msg.sender, nonce,reward, pool, depositDuration, stakeDuration);
        if (!IERC20(reward).approve(predicted, pool)) revert("approve vault failed");
        SmartVault vault = new SmartVault{salt: salt}(asset, reward, pool, depositDuration, stakeDuration);
        if (address(vault) != predicted) revert("address mismatch");
        unchecked { count[msg.sender] = nonce + 1; }
        return address(vault);
    }
    function predict(address creator, address reward, uint256 pool, uint24  depositDuration, uint24  stakeDuration) external view returns (address) {
        return _predict(creator, count[creator], reward, pool, depositDuration, stakeDuration);
    }
    function _predict(address creator, uint256 nonce, address reward, uint256 pool, uint24  depositDuration, uint24  stakeDuration) internal view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(creator, nonce));
        bytes32 hash = keccak256(abi.encodePacked(type(SmartVault).creationCode,abi.encode(asset, reward, pool, depositDuration, stakeDuration)));
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, hash)))));
    }
}
