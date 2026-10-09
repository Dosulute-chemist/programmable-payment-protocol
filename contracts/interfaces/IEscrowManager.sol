// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IEscrowManager {
    enum SettlementMode {
        PayerRelease,
        Deadline,
        Resolver
    }

    function createEscrowFromPayment(
        address payer,
        address recipient,
        address token,
        uint256 amount,
        SettlementMode mode,
        uint256 deadline,
        address resolver,
        bytes32 agreementReference
    ) external payable returns (uint256 escrowId);
}
