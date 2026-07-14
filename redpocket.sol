// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract RedPocket {
    bytes32 public immutable secretHash;

    mapping(address => bytes32) public commitments;
    mapping(address => uint256) public commitBlock;

    constructor() payable {
        secretHash = 0x00f5286e7b80b72a68bd577676c45abce5ea8a9bc10cf7b9c292bae1c01ae06f;
    }

    // 防MEV bot
    function commit(bytes32 commitment) external {
        require(address(this).balance > 0, "Claimed");
        require(commitments[msg.sender] == bytes32(0), "Committed");
        commitments[msg.sender] = commitment;
        commitBlock[msg.sender] = block.number;
    }

    function reveal(bytes32 secret) external {
        require(address(this).balance > 0, "Claimed");
        bytes32 expected = keccak256(abi.encodePacked(secret, msg.sender));
        require(commitments[msg.sender] == expected, "Invalid");
        require(block.number > commitBlock[msg.sender] + 1, "Too soon");
        require(keccak256(abi.encodePacked(secret)) == secretHash, "Wrong");
        uint256 amount = address(this).balance;
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Failed");
    }

    receive() external payable {}
}
