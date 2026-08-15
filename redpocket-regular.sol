// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

contract RedPocket {
    address public immutable signer; // 公钥对应地址
    uint256 public nonce;

    constructor(address _signer) payable {
        signer = _signer; // 记录公钥对应地址
    }

    function claim(bytes calldata signature) external {
        require(address(this).balance > 0, "E1"); // 合约余额不足
        require(signature.length == 65, "E2"); // 签名长度错误

        // 拆分签名为r s v
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset) // sig[:32] = sig[0:32]
            s := calldataload(add(signature.offset, 32)) // sig[32:][:32] = sig[32:64]
            v := byte(0, calldataload(add(signature.offset, 64))) // sig[64:][:32][0] = sig[64]
        }
        if (v < 27) { // 兼容不同钱包 ecrecover接受v == 27 or v == 28
            v += 27;
        }

        // 构造被签名内容
        bytes32 messageHash = keccak256(abi.encodePacked(
            address(this), // 合约地址 防签名被用于其他合约
            msg.sender, // 领取者地址 防MEVbot抢跑和冒领
            nonce,
            block.chainid // 链ID 防跨链重放
        ));
        bytes32 ethSignedHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            messageHash
        ));

        // 验签
        address recovered = ecrecover(ethSignedHash, v, r, s);
        require(recovered == signer, "E3"); // 签名验证失败

        (bool success, ) = payable(msg.sender).call{value: address(this).balance}(""); // 转出所有ETH
        require(success, "E4"); // 未知原因交易失败
        nonce++
    }

    receive() external payable {}
}
