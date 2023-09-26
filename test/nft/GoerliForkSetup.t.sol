// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import 'forge-std/Test.sol';
import {GoerliParams, WETH, FTRG, WBTC, STONES, TOTEM} from '@script/GoerliParams.s.sol';
import {GoerliDeployment} from '@script/GoerliDeployment.s.sol';
import {ODProxy} from '@contracts/proxies/ODProxy.sol';
import {NFTRenderer} from '@contracts/proxies/NFTRenderer.sol';

contract GoerliForkSetup is Test, GoerliDeployment {
  uint256 public currSafeId = 10;

  bytes32 public cType = vm.envBytes32('CTYPE_SYM');
  address public cAddr = vm.envAddress('CTYPE_ADDR');

  // TODO replace with Arbitrum addrs
  address public ARB_WBTC = address(0);
  address public ARB_STONES = address(0);
  address public ARB_TOTEM = address(0);

  address public alice = vm.envAddress('ARB_GOERLI_PUBLIC1'); // 0x23
  address public bob = vm.envAddress('ARB_GOERLI_PUBLIC2'); // 0x37
  address aliceProxy;

  function setUp() public virtual {
    vm.label(alice, 'Alice');
    vm.label(bob, 'Bob');
    aliceProxy = deployOrFind(alice);
    vm.label(aliceProxy, 'A-Proxy');
  }

  // --- helper functions ---

  function deployOrFind(address owner) public returns (address) {
    address proxy = vault721.getProxy(owner);
    if (proxy == address(0)) {
      return address(vault721.build(owner));
    } else {
      return proxy;
    }
  }

  function openSafe(bytes32 _cType, address _proxy) public returns (uint256 _safeId) {
    bytes memory payload = abi.encodeWithSelector(basicActions.openSAFE.selector, address(safeManager), _cType, _proxy);
    bytes memory safeData = ODProxy(_proxy).execute(address(basicActions), payload);
    _safeId = abi.decode(safeData, (uint256));
  }

  function depositCollatAndGenDebt(
    bytes32 _cType,
    uint256 _safeId,
    uint256 _collatAmount,
    uint256 _deltaWad,
    address _proxy
  ) public {
    bytes memory payload = abi.encodeWithSelector(
      basicActions.lockTokenCollateralAndGenerateDebt.selector,
      address(safeManager),
      address(taxCollector),
      address(collateralJoin[_cType]),
      address(coinJoin),
      _safeId,
      _collatAmount,
      _deltaWad
    );
    ODProxy(_proxy).execute(address(basicActions), payload);
  }
}