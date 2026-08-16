// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

contract RedPocket {
    address public owner; // 合约所有者地址
    address public signer; // 公钥对应地址
    uint256 nonce;
    uint256 public remainClaims; // 剩余可领取次数
    uint256 constant minAmount = 1e12; // 保底金额

    event claimed(address user, uint256 amount, uint256 remainClaims);
    event refilled(uint256 balance, uint256 remainClaims);

    constructor(address _owner, address _signer, uint8 _remainClaims) payable {
        signer = _signer; // 初始化公钥对应地址
        owner = _owner; // 初始化合约所有者地址
        remainClaims = _remainClaims; // 初始化剩余可领取次数
    }

    function claim(bytes calldata signature) external {
        require(remainClaims > 0, "E1"); // 已领完
        require(address(this).balance > 0, "E2"); // 智能合约余额不足
        require(signature.length == 65, "E3"); // 签名长度错误

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
        require(recovered == signer, "E4"); // 签名验证失败

        uint256 amount; // 随机领取数额(单位wei)

        if (remainClaims == 1) { // 若只剩一次领取次数 领走剩余全部
            amount = remainClaims;
        } else { // 若还能领大于一次 随机拼手气 最多可领平均值的二倍 最少能拿到保底 且保证其他用户至少拿到保底
            uint256 avg = address(this).balance / remainClaims;
            uint256 maxAmount = avg * 2;

            uint256 minLeave = minAmount * (remainClaims - 1);
            if (maxAmount > remainClaims - minLeave) {
                maxAmount = remainClaims - minLeave;
            }
            if (maxAmount < minAmount) {
                maxAmount = minAmount;
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
            uint256 range = maxAmount - minAmount + 1;
            amount = minAmount + (randSeed % range); // 计算本次领取数额
        }
        (bool success, ) = payable(msg.sender).call{value: amount}(""); // 转账amount数量ETH
        require(success, "E6"); // 未知原因交易失败
        remainClaims -= 1;
        emit claimed(msg.sender, amount, remainClaims);
    }

    // OWNER ONLY
    function transferOwnership(address newOwner) external {
        owner = newOwner;
    }

    // OWNER ONLY
    function refill(uint256 claimCount) external payable {
        remainClaims = claimCount;
        emit refilled(address(this).balance, remainClaims);
    }

    // 允许捐赠
    receive() external payable {}
}
