// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

contract RedPocket {
    address public immutable signer; // 公钥对应地址
    uint256 public claimCount; // 已领取次数
    uint256 public constant MAX_CLAIMS = 5; // 最多可领取次数
    uint256 public constant MIN_AMOUNT = 1e12; // 保底金额

    constructor(address _signer) payable {
        signer = _signer; // 记录公钥对应地址
    }

    function claim(uint256 nonce, bytes calldata signature) external {
        require(claimCount < MAX_CLAIMS, "E1"); // 已领完
        require(nonce == claimCount, "E2"); // Nonce错误
        require(address(this).balance > 0, "E3"); // 合约余额不足
        require(signature.length == 65, "E4"); // 签名长度错误

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
        require(recovered == signer, "E5"); // 签名验证失败

        // 二倍均值法随机拼手气 最多可领平均值的二倍 最少能拿到保底
        uint256 remainingClaims = MAX_CLAIMS - claimCount; // 剩余可领取次数
        uint256 remaining = address(this).balance; // 剩余余额
        uint256 amount; // 随机领取数额(单位wei)

        if (remainingClaims == 1) { // 若只剩一次领取次数 领走剩余全部
            amount = remaining;
        } else { // 若还能领大于一次 随机拼手气
            uint256 avg = remaining / remainingClaims;
            uint256 maxAmount = avg * 2;

            uint256 minLeave = MIN_AMOUNT * (remainingClaims - 1);
            if (maxAmount > remaining - minLeave) {
                maxAmount = remaining - minLeave;
            }
            if (maxAmount < MIN_AMOUNT) {
                maxAmount = MIN_AMOUNT;
            }

            // 随机生成随机数种子
            uint256 randSeed = uint256(keccak256(abi.encodePacked(
                block.prevrandao, // 前一个区块的randao随机值
                block.timestamp, // 区块时间戳
                msg.sender, // 领取者地址
                nonce,
                r,
                s
            )));
            uint256 range = maxAmount - MIN_AMOUNT + 1;
            amount = MIN_AMOUNT + (randSeed % range); // 计算本次领取数额
        }
        claimCount += 1;
        (bool success, ) = payable(msg.sender).call{value: amount}(""); // 转账amount数量ETH
        require(success, "E6"); // 未知原因交易失败
    }

    receive() external payable {}
}
