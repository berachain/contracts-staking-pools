// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Vm } from "forge-std/Test.sol";

contract MockBGT is ERC20 {
    error NotEnoughBoostedBalance();

    struct QueuedBoost {
        uint32 blockNumberLast;
        uint128 balance;
    }

    struct QueuedDropBoost {
        uint32 blockNumberLast;
        uint128 balance;
    }

    struct UserBoost {
        uint128 boost;
        uint128 queuedBoost;
    }

    Vm public vm = Vm(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D)); // hevm cheat code (Base.sol)
    mapping(address account => mapping(bytes pubkey => QueuedBoost)) public boostedQueue;
    mapping(address account => mapping(bytes pubkey => QueuedDropBoost)) public dropBoostQueue;
    mapping(address account => mapping(bytes pubkey => uint128)) public boosted;
    mapping(address account => UserBoost) internal userBoosts;
    mapping(bytes pubkey => uint128) public boostees;

    uint256 public totalBoosts;

    constructor() ERC20("Mocked BGT", "MBGT") { }

    function queueBoost(bytes calldata pubkey, uint128 amount) external {
        userBoosts[msg.sender].queuedBoost += amount;
        unchecked {
            QueuedBoost storage qb = boostedQueue[msg.sender][pubkey];
            uint128 balance = qb.balance + amount;
            (qb.balance, qb.blockNumberLast) = (balance, uint32(block.number));
        }
    }

    function cancelBoost(bytes calldata pubkey, uint128 amount) external {
        QueuedBoost storage qb = boostedQueue[msg.sender][pubkey];
        qb.balance -= amount;
        unchecked {
            userBoosts[msg.sender].queuedBoost -= amount;
        }
    }

    function activateBoost(address user, bytes calldata pubkey) external {
        QueuedBoost storage qb = boostedQueue[user][pubkey];
        (, uint128 amount) = (qb.blockNumberLast, qb.balance);

        totalBoosts += amount;
        unchecked {
            boostees[pubkey] += amount;
            boosted[user][pubkey] += amount;
            UserBoost storage userBoost = userBoosts[user];
            (uint128 boost, uint128 _queuedBoost) = (userBoost.boost, userBoost.queuedBoost);
            (userBoost.boost, userBoost.queuedBoost) = (boost + amount, _queuedBoost - amount);
        }
        delete boostedQueue[user][pubkey];

        // IBGTStaker(staker).stake(user, amount);
    }

    function queueDropBoost(bytes calldata pubkey, uint128 amount) external {
        QueuedDropBoost storage qdb = dropBoostQueue[msg.sender][pubkey];
        uint128 dropBalance = qdb.balance + amount;
        if (boosted[msg.sender][pubkey] < dropBalance) revert NotEnoughBoostedBalance();
        (qdb.balance, qdb.blockNumberLast) = (dropBalance, uint32(block.number));
    }

    function cancelDropBoost(bytes calldata pubkey, uint128 amount) external {
        QueuedDropBoost storage qdb = dropBoostQueue[msg.sender][pubkey];
        qdb.balance -= amount;
    }

    function dropBoost(address user, bytes calldata pubkey) external {
        QueuedDropBoost storage qdb = dropBoostQueue[user][pubkey];
        (, uint128 amount) = (qdb.blockNumberLast, qdb.balance);
        unchecked {
            boosted[user][pubkey] -= amount;
            totalBoosts -= amount;
            userBoosts[user].boost -= amount;
            boostees[pubkey] -= amount;
        }
        delete dropBoostQueue[user][pubkey];
        // IBGTStaker(staker).withdraw(user, amount);
    }

    function redeem(address to, uint256 amount) external {
        _burn(msg.sender, amount);
        vm.deal(to, to.balance + amount);
    }

    function unboostedBalanceOf(address account) external view returns (uint256) {
        UserBoost storage userBoost = userBoosts[account];
        (uint128 boost, uint128 _queuedBoost) = (userBoost.boost, userBoost.queuedBoost);
        return balanceOf(account) - boost - _queuedBoost;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
