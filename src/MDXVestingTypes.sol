// Layout:
//     - pragma
//     - imports
//     - interfaces, libraries, contracts
//     - type declarations
//     - state variables
//     - events
//     - errors
//     - modifiers
//     - functions
//         - constructor
//         - receive function (if exists)
//         - fallback function (if exists)
//         - external
//         - public
//         - internal
//         - private
//         - view and pure functions

// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title MDX-VESTING TYPE.
 * @author Monadex Labs -- Ola Hamid.
 * @notice types decleartion for vesting
 */
contract MDXVestingTypes {
    struct investorsDetail {
        bytes32 investorID;
        uint256 investorIDX;
    }

    struct vestingDetail {
        address investor;
        /// interval day to start the vesting process, should not be zero
        uint256 startCliff;
        /// current timstamp in which the vesting process is being started
        uint256 startDate;
        /// amount in seconds that the vesting process will last for
        uint256 duration;
        /// amount of slashes that the vesting process will be
        uint256 frequency;
        bool retrievable;
        uint256 amountTotal;
        uint256 retrieved;
        bool cancel;
    }
}
