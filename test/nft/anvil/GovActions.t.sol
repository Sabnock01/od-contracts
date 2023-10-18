// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {AnvilFork} from '@test/nft/anvil/AnvilFork.t.sol';
import {Vault721} from '@contracts/proxies/Vault721.sol';
import {ODGovernor} from '@contracts/gov/ODGovernor.sol';
import {ICollateralAuctionHouse} from '@interfaces/ICollateralAuctionHouse.sol';
import {WAD, RAY, RAD} from '@libraries/Math.sol';
import {IGovernor} from '@openzeppelin/governance/IGovernor.sol';

// forge t --fork-url $URL --match-contract GovActionsAnvil -vvvvv

contract GovActionsAnvil is AnvilFork {
  uint256 constant MINUS_0_5_PERCENT_PER_HOUR = 999_998_607_628_240_588_157_433_861;
  /**
   * @notice ProposalState:
   * Pending = 0
   * Active = 1
   * Canceled = 2
   * Defeated = 3
   * Succeeded = 4
   * Queued = 5
   * Expired = 6
   * Executed = 7
   */
  IGovernor.ProposalState public propState;

  /**
   * @dev params for testing, do not use for production
   */
  ICollateralAuctionHouse.CollateralAuctionHouseParams _cahCParams = ICollateralAuctionHouse
    .CollateralAuctionHouseParams({
    minimumBid: WAD, // 1 COINs
    minDiscount: WAD, // no discount
    maxDiscount: 0.9e18, // -10%
    perSecondDiscountUpdateRate: MINUS_0_5_PERCENT_PER_HOUR
  });

  // test
  function testExecuteProp() public {
    uint256 startBlock = block.number;
    uint256 startTime = block.timestamp;
    emit log_named_uint('Block', startBlock);
    emit log_named_uint('Time', startTime);
    // ODGovernor dao = ODGovernor(payable(ODGovernor_Address));
    ODGovernor dao = odGovernor;

    (
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description,
      bytes32 descriptionHash
    ) = generateParams();

    vm.startPrank(ALICE);
    uint256 propId = dao.propose(targets, values, calldatas, description);
    vm.stopPrank();

    assertEq(propId, dao.hashProposal(targets, values, calldatas, descriptionHash));

    propState = dao.state(propId); // returns 0 (pending)

    emit log_named_uint('Voting Delay:', dao.votingDelay());
    emit log_named_uint('Voting Period:', dao.votingPeriod());

    vm.roll(startBlock + 2);
    vm.warp(startTime + 30 seconds);
    emit log_named_uint('Block', block.number);
    emit log_named_uint('Time', block.timestamp);

    propState = dao.state(propId);

    vm.startPrank(ALICE);
    // ALICE holds no governance tokens, so should not effect outcome
    dao.castVote(propId, 0);
    vm.stopPrank();

    propState = dao.state(propId); // returns 1 (active)

    vm.startPrank(BOB);
    // BOB holds 33% of governance tokens (@bug showing weight at 0)
    dao.castVote(propId, 1);
    vm.stopPrank();

    propState = dao.state(propId); // returns 1 (active)

    vm.roll(startBlock + 17);
    vm.warp(startTime + 255 seconds);
    emit log_named_uint('Block', block.number);
    emit log_named_uint('Time', block.timestamp);

    propState = dao.state(propId); // returns 3 (defeated)

    // TODO: pass `execute`
    dao.execute(targets, values, calldatas, descriptionHash);
  }

  // helpers
  function generateParams()
    public
    returns (
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description,
      bytes32 descriptionHash
    )
  {
    targets = new address[](2);
    targets[0] = address(collateralJoinFactory);
    targets[1] = address(collateralAuctionHouseFactory);

    values = new uint256[](2);
    values[0] = 0;
    values[1] = 0;

    bytes memory calldata0 = abi.encodeWithSignature('deployCollateralJoin(bytes32,address)', newCType, newCAddress);
    bytes memory calldata1 = abi.encodeWithSignature(
      'deployCollateralAuctionHouse(bytes32,ICollateralAuctionHouse.CollateralAuctionHouseParams)',
      newCType,
      _cahCParams
    );

    calldatas = new bytes[](2);
    calldatas[0] = calldata0;
    calldatas[1] = calldata1;

    description = 'Add collateral type';

    descriptionHash = keccak256(bytes(description));
  }
}
