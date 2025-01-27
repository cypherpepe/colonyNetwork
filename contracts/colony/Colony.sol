// SPDX-License-Identifier: GPL-3.0-or-later
/*
  This file is part of The Colony Network.

  The Colony Network is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  The Colony Network is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with The Colony Network. If not, see <http://www.gnu.org/licenses/>.
*/

pragma solidity 0.8.27;
pragma experimental ABIEncoderV2;

import { ERC20Extended } from "./../common/ERC20Extended.sol";
import { Multicall } from "./../common/Multicall.sol";
import { IEtherRouter } from "./../common/IEtherRouter.sol";
import { BasicMetaTransaction } from "./../common/BasicMetaTransaction.sol";
import { ITokenLocking } from "./../tokenLocking/ITokenLocking.sol";
import { IColonyNetwork } from "./../colonyNetwork/IColonyNetwork.sol";
import { PatriciaTreeProofs } from "./../patriciaTree/PatriciaTreeProofs.sol";
import { ColonyStorage } from "./ColonyStorage.sol";
import { ColonyAuthority } from "./ColonyAuthority.sol";
import { ColonyExtension } from "./../extensions/ColonyExtension.sol";

contract Colony is BasicMetaTransaction, Multicall, ColonyStorage, PatriciaTreeProofs {
  // This function, exactly as defined, is used in build scripts. Take care when updating.
  // Version number should be upped with every change in Colony or its dependency contracts or libraries.
  // prettier-ignore
  function version() public pure returns (uint256 colonyVersion) { return 17; }

  function getColonyNetwork() public view returns (address) {
    return colonyNetworkAddress;
  }

  function getToken() public view returns (address) {
    return token;
  }

  function annotateTransaction(bytes32 _txHash, string memory _metadata) public always {
    emit Annotation(msgSender(), _txHash, _metadata);
  }

  function emitDomainReputationReward(
    uint256 _domainId,
    address _user,
    int256 _amount
  ) public stoppable auth {
    require(_amount > 0, "colony-reward-must-be-positive");
    require(domainExists(_domainId), "colony-domain-does-not-exist");
    IColonyNetwork(colonyNetworkAddress).appendReputationUpdateLog(
      _user,
      _amount,
      domains[_domainId].skillId
    );

    emit ArbitraryReputationUpdate(msgSender(), _user, domains[_domainId].skillId, _amount);
  }

  function emitSkillReputationReward(
    uint256 _skillId,
    address _user,
    int256 _amount
  ) public stoppable auth validLocalSkill(_skillId) {
    require(_amount > 0, "colony-reward-must-be-positive");
    IColonyNetwork(colonyNetworkAddress).appendReputationUpdateLog(_user, _amount, _skillId);

    emit ArbitraryReputationUpdate(msgSender(), _user, _skillId, _amount);
  }

  function emitDomainReputationPenalty(
    uint256 _permissionDomainId,
    uint256 _childSkillIndex,
    uint256 _domainId,
    address _user,
    int256 _amount
  ) public stoppable authDomain(_permissionDomainId, _childSkillIndex, _domainId) {
    require(_amount <= 0, "colony-penalty-cannot-be-positive");
    IColonyNetwork(colonyNetworkAddress).appendReputationUpdateLog(
      _user,
      _amount,
      domains[_domainId].skillId
    );

    emit ArbitraryReputationUpdate(msgSender(), _user, domains[_domainId].skillId, _amount);
  }

  function emitSkillReputationPenalty(
    uint256 _skillId,
    address _user,
    int256 _amount
  ) public stoppable auth validLocalSkill(_skillId) {
    require(_amount <= 0, "colony-penalty-cannot-be-positive");
    IColonyNetwork(colonyNetworkAddress).appendReputationUpdateLog(_user, _amount, _skillId);

    emit ArbitraryReputationUpdate(msgSender(), _user, _skillId, _amount);
  }

  function editColony(string memory _metadata) public stoppable auth {
    emit ColonyMetadata(msgSender(), _metadata);
  }

  function editColonyByDelta(string memory _metadataDelta) public stoppable auth {
    emit ColonyMetadataDelta(msgSender(), _metadataDelta);
  }

  function bootstrapColony(address[] memory _users, int[] memory _amounts) public stoppable auth {
    require(
      DEPRECATED_taskCount == 0 && DEPRECATED_paymentCount == 0 && expenditureCount == 0,
      "colony-not-in-bootstrap-mode"
    );
    require(_users.length == _amounts.length, "colony-bootstrap-bad-inputs");

    for (uint256 i = 0; i < _users.length; i++) {
      require(_amounts[i] >= 0, "colony-bootstrap-bad-amount-input");
      require(
        uint256(_amounts[i]) <= fundingPots[1].balance[token],
        "colony-bootstrap-not-enough-tokens"
      );
      fundingPots[1].balance[token] = fundingPots[1].balance[token] - uint256(_amounts[i]);
      nonRewardPotsTotal[token] = nonRewardPotsTotal[token] - uint256(_amounts[i]);
    }

    // After doing all the local storage changes, then do all the external calls
    for (uint256 i = 0; i < _users.length; i++) {
      require(
        ERC20Extended(token).transfer(_users[i], uint256(_amounts[i])),
        "colony-bootstrap-token-transfer-failed"
      );
      IColonyNetwork(colonyNetworkAddress).appendReputationUpdateLog(
        _users[i],
        _amounts[i],
        domains[1].skillId
      );
    }

    emit ColonyBootstrapped(msgSender(), _users, _amounts);
  }

  function burnTokens(address _token, uint256 _amount) public stoppable auth {
    // Check the root funding pot has enought
    require(fundingPots[1].balance[_token] >= _amount, "colony-not-enough-tokens");
    fundingPots[1].balance[_token] -= _amount;

    ERC20Extended(_token).burn(_amount);

    emit TokensBurned(msgSender(), _token, _amount);
  }

  function mintTokens(uint _wad) public stoppable auth {
    ERC20Extended(token).mint(address(this), _wad); // ignore-swc-107

    emit TokensMinted(msgSender(), address(this), _wad);
  }

  function mintTokensFor(address _guy, uint _wad) public stoppable auth {
    ERC20Extended(token).mint(_guy, _wad); // ignore-swc-107

    emit TokensMinted(msgSender(), _guy, _wad);
  }

  function registerColonyLabel(
    string memory colonyName,
    string memory orbitdb
  ) public stoppable auth {
    IColonyNetwork(colonyNetworkAddress).registerColonyLabel(colonyName, orbitdb);
  }

  function updateColonyOrbitDB(string memory orbitdb) public stoppable auth {
    IColonyNetwork(colonyNetworkAddress).updateColonyOrbitDB(orbitdb);
  }

  function setNetworkFeeInverse(uint256 _feeInverse) public stoppable auth {
    IColonyNetwork(colonyNetworkAddress).setFeeInverse(_feeInverse); // ignore-swc-107
  }

  function setPayoutWhitelist(address _token, bool _status) public stoppable auth {
    IColonyNetwork(colonyNetworkAddress).setPayoutWhitelist(_token, _status); // ignore-swc-107
  }

  function setReputationMiningCycleReward(uint256 _amount) public stoppable auth {
    IColonyNetwork(colonyNetworkAddress).setReputationMiningCycleReward(_amount);
  }

  function addNetworkColonyVersion(uint256 _version, address _resolver) public stoppable auth {
    IColonyNetwork(colonyNetworkAddress).addColonyVersion(_version, _resolver);
  }

  function setColonyBridgeAddress(address _bridgeAddress) public stoppable auth {
    IColonyNetwork(colonyNetworkAddress).setColonyBridgeAddress(_bridgeAddress);
  }

  function initialiseReputationMining(
    uint256 miningChainId,
    bytes32 newHash,
    uint256 newNLeaves
  ) public stoppable auth {
    IColonyNetwork(colonyNetworkAddress).initialiseReputationMining(
      miningChainId,
      newHash,
      newNLeaves
    );
  }

  function addExtensionToNetwork(bytes32 _extensionId, address _resolver) public stoppable auth {
    IColonyNetwork(colonyNetworkAddress).addExtensionToNetwork(_extensionId, _resolver);
  }

  function installExtension(bytes32 _extensionId, uint256 _version) public stoppable auth {
    IColonyNetwork(colonyNetworkAddress).installExtension(_extensionId, _version);
  }

  function upgradeExtension(bytes32 _extensionId, uint256 _newVersion) public stoppable auth {
    IColonyNetwork(colonyNetworkAddress).upgradeExtension(_extensionId, _newVersion);
  }

  function deprecateExtension(bytes32 _extensionId, bool _deprecated) public stoppable auth {
    IColonyNetwork(colonyNetworkAddress).deprecateExtension(_extensionId, _deprecated);
  }

  function uninstallExtension(bytes32 _extensionId) public stoppable auth {
    IColonyNetwork(colonyNetworkAddress).uninstallExtension(_extensionId);
  }

  function addLocalSkill() public stoppable auth {
    require(rootLocalSkill != 0, "colony-local-skill-tree-not-initialised");

    uint256 newLocalSkill = IColonyNetwork(colonyNetworkAddress).addSkill(rootLocalSkill);
    localSkills[newLocalSkill] = LocalSkill({ exists: true, deprecated: false });

    emit LocalSkillAdded(msgSender(), newLocalSkill);
  }

  function deprecateLocalSkill(uint256 _localSkillId, bool _deprecated) public stoppable auth {
    LocalSkill storage localSkill = localSkills[_localSkillId];

    if (localSkill.exists && localSkill.deprecated != _deprecated) {
      localSkill.deprecated = _deprecated;

      emit LocalSkillDeprecated(msgSender(), _localSkillId, _deprecated);
    } else if (DEPRECATED_localSkills[_localSkillId] && _deprecated) {
      // Handle local skills created prior to colonyNetwork#1280
      localSkills[_localSkillId] = LocalSkill({ exists: true, deprecated: _deprecated });
      delete DEPRECATED_localSkills[_localSkillId];

      emit LocalSkillDeprecated(msgSender(), _localSkillId, _deprecated);
    }
  }

  function getRootLocalSkill() public view returns (uint256) {
    return rootLocalSkill;
  }

  function getLocalSkill(uint256 _localSkillId) public view returns (LocalSkill memory localSkill) {
    localSkill = localSkills[_localSkillId];
  }

  function verifyReputationProof(
    bytes memory key,
    bytes memory value,
    uint256 branchMask,
    bytes32[] memory siblings
  ) public view returns (bool) {
    uint256 colonyAddress;
    uint256 skillid;
    uint256 userAddress;
    assembly {
      colonyAddress := mload(add(key, 32))
      skillid := mload(add(key, 52)) // Colony address was 20 bytes long, so add 20 bytes
      userAddress := mload(add(key, 84)) // Skillid was 32 bytes long, so add 32 bytes
    }
    colonyAddress >>= 96;
    userAddress >>= 96;

    // Require that the user is proving their own reputation in this colony.
    if (
      address(uint160(colonyAddress)) != address(this) ||
      address(uint160(userAddress)) != msgSender()
    ) {
      return false;
    }

    // Get roothash from colonynetwork
    bytes32 rootHash = IColonyNetwork(colonyNetworkAddress).getReputationRootHash();
    bytes32 impliedHash = getImpliedRootHashKey(key, value, branchMask, siblings);
    if (rootHash != impliedHash) {
      return false;
    }

    return true;
  }

  function upgrade(uint256 _newVersion) public always auth {
    // Upgrades can only go up in version, one at a time
    uint256 currentVersion = version();
    require(_newVersion == currentVersion + 1, "colony-version-must-be-one-newer");
    // Requested version has to be registered
    address newResolver = IColonyNetwork(colonyNetworkAddress).getColonyVersionResolver(
      _newVersion
    );
    require(newResolver != address(0x0), "colony-version-must-be-registered");
    IEtherRouter currentColony = IEtherRouter(address(this));
    currentColony.setResolver(newResolver);
    // This is deliberately an external call, because we don't know what we need to do for our next upgrade yet.
    // Because it's called after setResolver, it'll do the new finishUpgrade, which will be populated with what we know
    // we need to do once we know what's in it!
    this.finishUpgrade();

    emit ColonyUpgraded(msgSender(), currentVersion, _newVersion);
  }

  function finishUpgrade() public always {
    // Leaving as example for what is typically done here
    // ColonyAuthority colonyAuthority = ColonyAuthority(address(authority));
    // bytes4 sig;
    // sig = bytes4(keccak256("cancelExpenditureViaArbitration(uint256,uint256,uint256)"));
    // colonyAuthority.setRoleCapability(uint8(ColonyRole.Arbitration), address(this), sig, true);
  }

  function getMetatransactionNonce(address _user) public view override returns (uint256 nonce) {
    return metatransactionNonces[_user];
  }

  function incrementMetatransactionNonce(address _user) internal override {
    // We need to protect the metatransaction nonce slots, otherwise those with recovery
    // permissions could replay metatransactions, which would be a disaster.
    // What slot are we setting?
    // This mapping is in slot 34 (see ColonyStorage.sol);
    uint256 slot = uint256(
      keccak256(abi.encode(uint256(uint160(_user)), uint256(METATRANSACTION_NONCES_SLOT)))
    );
    protectSlot(slot);
    metatransactionNonces[_user] += 1;
  }

  function checkNotAdditionalProtectedVariable(uint256 _slot) public pure {
    require(_slot != COLONY_NETWORK_SLOT, "colony-protected-variable");
    require(_slot != ROOT_LOCAL_SKILL_SLOT, "colony-protected-variable");
  }

  function approveStake(address _approvee, uint256 _domainId, uint256 _amount) public stoppable {
    approvals[msgSender()][_approvee][_domainId] += _amount;

    ITokenLocking(tokenLockingAddress).approveStake(msgSender(), _amount, token);
  }

  function obligateStake(address _user, uint256 _domainId, uint256 _amount) public stoppable {
    approvals[_user][msgSender()][_domainId] -= _amount;
    obligations[_user][msgSender()][_domainId] += _amount;

    ITokenLocking(tokenLockingAddress).obligateStake(_user, _amount, token);
  }

  function deobligateStake(address _user, uint256 _domainId, uint256 _amount) public stoppable {
    obligations[_user][msgSender()][_domainId] -= _amount;

    ITokenLocking(tokenLockingAddress).deobligateStake(_user, _amount, token);
  }

  function transferStake(
    uint256 _permissionDomainId,
    uint256 _childSkillIndex,
    address _obligator,
    address _user,
    uint256 _domainId,
    uint256 _amount,
    address _beneficiary
  ) public stoppable authDomain(_permissionDomainId, _childSkillIndex, _domainId) {
    obligations[_user][_obligator][_domainId] -= _amount;

    ITokenLocking(tokenLockingAddress).transferStake(_user, _amount, token, _beneficiary);
  }

  function getApproval(
    address _user,
    address _obligator,
    uint256 _domainId
  ) public view returns (uint256) {
    return approvals[_user][_obligator][_domainId];
  }

  function getObligation(
    address _user,
    address _obligator,
    uint256 _domainId
  ) public view returns (uint256) {
    return obligations[_user][_obligator][_domainId];
  }

  function unlockToken() public stoppable auth {
    ERC20Extended(token).unlock();

    emit TokenUnlocked(msgSender());
  }

  function getTokenApproval(address _token, address _spender) public view returns (uint256) {
    return tokenApprovals[_token][_spender];
  }

  function getTotalTokenApproval(address _token) public view returns (uint256) {
    return tokenApprovalTotals[_token];
  }

  // Deprecated view functions for Tasks and Payments

  function getTaskCount() public view returns (uint256) {
    return DEPRECATED_taskCount;
  }

  function getTaskChangeNonce(uint256 _id) public view returns (uint256) {
    return DEPRECATED_taskChangeNonces[_id];
  }

  function getTaskWorkRatingSecretsInfo(uint256 _id) public view returns (uint256, uint256) {
    return (DEPRECATED_taskWorkRatings[_id].count, DEPRECATED_taskWorkRatings[_id].timestamp);
  }

  function getTaskWorkRatingSecret(uint256 _id, uint8 _role) public view returns (bytes32) {
    return DEPRECATED_taskWorkRatings[_id].secret[_role];
  }

  function getTaskRole(uint256 _id, uint8 _role) public view returns (Role memory role) {
    role = DEPRECATED_tasks[_id].roles[_role];
  }

  function getTask(
    uint256 _id
  )
    public
    view
    returns (bytes32, bytes32, TaskStatus, uint256, uint256, uint256, uint256, uint256[] memory)
  {
    Task storage t = DEPRECATED_tasks[_id];
    return (
      t.specificationHash,
      t.deliverableHash,
      t.status,
      t.dueDate,
      t.fundingPotId,
      t.completionTimestamp,
      t.domainId,
      t.skills
    );
  }

  function getPayment(uint256 _id) public view returns (Payment memory) {
    return DEPRECATED_payments[_id];
  }

  function getPaymentCount() public view returns (uint256) {
    return DEPRECATED_paymentCount;
  }
}
