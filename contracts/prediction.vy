 # pragma version ~=0.4.0
"""
@title `prediction` Prediction Market Game 
@custom:contract-name prediction
@license GNU Affero General Public License v3.0 only
@author rabuawad
"""


# @dev We import the `IERC20` interface,
# which is a built-in interface of the Vyper compiler.
from ethereum.ercs import IERC20


# @dev We import the `IERC20Detailed` interface,
# which is a built-in interface of the Vyper compiler.
from ethereum.ercs import IERC20Detailed


# @dev We import the `AggregatorV3` interface.
from .interfaces import IAggregatorV3


# @dev We import and initialise the `ownable` module.
from snekmate.auth import ownable as ow
initializes: ow


# @dev We export all `external` functions
# from the `ownable` module.
exports: ow.__interface__


# @dev Enum representing the position of a bet,
# either Bull (Up) or Bear (Down)
flag Position:
    Bull
    Bear


# @dev Stores the Round data used for tracking
# each prediction round in the contract
struct Round:
    epoch: uint256
    startTimestamp: uint256
    lockTimestamp: uint256
    closeTimestamp: uint256
    lockPrice: int256
    closePrice: int256
    lockOracleId: uint256
    closeOracleId: uint256
    totalAmount: uint256
    bullAmount: uint256
    bearAmount: uint256
    rewardBaseCalAmount: uint256
    rewardAmount: uint256
    oracleCalled: bool


# @dev Stores information about each bet,
# including position, amount, and claimed status
struct BetInfo:
    position: Position
    amount: uint256
    claimed: bool


# @dev Returns the address of operator
operator: public(address)


# @dev Tracks whether the genesis lock round has been triggered. This ensures
# that the price lock for the first round (genesis) is only done once.
genesisLockOnce: public(bool)


# @dev Tracks whether the genesis start round has been triggered. This ensures
# that the first round (genesis) starts only once and avoids multiple initiations.
genesisStartOnce: public(bool)


# @dev Returns the address of the underlying token
# used for the protocl.
asset: public(immutable(address))


# @dev Stores the ERC-20 interface object of the underlying
# token used for the protocol
_ASSET: immutable(IERC20)


# @dev Returns the address of the underlying oracle
# used for the protocl.
oracle: public(immutable(address))


# @dev Stores the Aggregator V3 interface object of the underlying
# oravle used for the protocol
_ORACLE: immutable(IAggregatorV3)


# @dev Returns the number of seconds for a valid 
# execution of a prediction round
bufferSeconds: public(uint256)


# @dev Returns the number of interval seconds
# between two prediction rounds
intervalSeconds: public(uint256)


# @dev Returns the minimum betting amount, denominated
# in Wei
minBetAmount: public(uint256)


# @dev Returns the fee taken by the protocol on
# each prediction round
treasuryFee: public(uint256)


# @dev Returns the amount stored in the protocol
# that has not been claimed
treasuryAmount: public(uint256)


# @dev Returns the current epoch for the ongoing
# prediction round
currentEpoch: public(uint256)


# @dev Returns if the protocol is Paused.
paused: public(bool)


# @dev Returns the latests Round ID from
# the Aggregator Oracle (converted from uint80) 
oracleLatestRoundId: public(uint256)


# @dev Returns the interfal of seconds
# between each oracle allowance update
# TODO: REVIEW DOC
oracleUpdateAllowance: public(uint256)


# @dev Returns The maximun fee that can be
# set by the protocol's owner. (10%)
MAX_TREASURY_FEE: public(constant(uint256)) = 1000 


# @dev Maps each epoch ID to a mapping of
# user addresses to their BetInfo.
ledger: public(HashMap[uint256, HashMap[address, BetInfo]])


# @dev Maps each epoch ID to the corresponding
# Round data.
rounds: public(HashMap[uint256, Round])


# @dev Maps each user's address to an unique ID used
# to keep track of the user rounds
_userRounds: HashMap[address, uint256]


# @dev Maps each user's address to an array of epochs
# in which they have participated. We use nested HashMaps
# to avoid the limitations of dynamic arrays in Vyper.
#
# Structure:
#   address => Index => Round ID
userRounds: public(HashMap[address, HashMap[uint256, uint256]])


# @dev Log when a user places a Bear bet
event BetBear:
    sender: indexed(address)
    epoch: indexed(uint256)
    amount: uint256


# @dev Log when a user places a Bull bet
event BetBull:
    sender: indexed(address)
    epoch: indexed(uint256)
    amount: uint256


# @dev Log when a user claims their winnings
event Claim:
    sender: indexed(address)
    epoch: indexed(uint256)
    amount: uint256


# @dev Log when a round ends
event EndRound:
    epoch: indexed(uint256)
    roundId: indexed(uint256)
    price: int256


# @dev Log when a round is locked
event LockRound:
    epoch: indexed(uint256)
    roundId: indexed(uint256)
    price: int256


# @dev Log when a new admin address is set
event NewAdminAddress:
    admin: address


# @dev Log when the buffer and interval seconds are updated
event NewBufferAndIntervalSeconds:
    bufferSeconds: uint256
    intervalSeconds: uint256


# @dev Log when a new minimum bet amount is set for a specific epoch
event NewMinBetAmount:
    epoch: indexed(uint256)
    minBetAmount: uint256


# @dev Log when a new treasury fee is set for a specific epoch
event NewTreasuryFee:
    epoch: indexed(uint256)
    treasuryFee: uint256


# @dev Log when a new operator address is set
event NewOperatorAddress:
    operator: address


# @dev Log when a new oracle address is set
event NewOracle:
    oracle: address


# @dev Log when a new oracle update allowance is set
event NewOracleUpdateAllowance:
    oracleUpdateAllowance: uint256


# @dev Log when the contract is paused for a specific epoch
event Pause:
    epoch: indexed(uint256)


# @dev Log when the contract is unpaused for a specific epoch
event Unpause:
    epoch: indexed(uint256)


# @dev Log when rewards are calculated for a specific epoch
event RewardsCalculated:
    epoch: indexed(uint256)
    rewardBaseCalAmount: uint256
    rewardAmount: uint256
    treasuryAmount: uint256


# @dev Log when a round starts
event StartRound:
    epoch: indexed(uint256)


# @dev Log when tokens are recovered from the contract
event TokenRecovery:
    token: indexed(address)
    amount: uint256


# @dev Log when the treasury claims its funds
event TreasuryClaim:
    amount: uint256


@deploy
@payable
def __init__(
    asset_: IERC20,
    oracle_: IAggregatorV3,
    adminAddress_: address,
    operatorAddress_: address,
    intervalSeconds_: uint256,
    bufferSeconds_: uint256,
    minBetAmount_: uint256,
    oracleUpdateAllowance_: uint256,
    treasuryFee_: uint256
):
    """
    @dev To omit the opcodes for checking the `msg.value`
         in the creation-time EVM bytecode, the constructor
         is declared as `payable`.
    @param asset_ The ERC-20 compatible (i.e. ERC-777 is also viable)
           underlying asset contract.
    @param oracle_ The address of the Chainlink Aggregator V3 oracle contract
           used to provide price feed data for the application.
    @param intervalSeconds_ The interval, in seconds, at which the price
           updates occur, determining how often the contract fetches new
           price information from the oracle.
    @param bufferSeconds_ The buffer time, in seconds, that must elapse
           before a new betting round can start, ensuring smooth transitions
           between rounds.
    @param minBetAmount_ The minimum amount of currency that users
           can wager when placing a bet, designed to ensure that bets
           are of a meaningful size.
    @param oracleUpdateAllowance_ The allowance period, in seconds,
           within which the oracle is expected to update the price feed,
           helping to maintain timely information.
    @param treasuryFee_ The fee collected for the treasury, which can be
           used for various operational costs or for funding other aspects
           of the protocol.
    @notice The `owner` role will be assigned to
            the `msg.sender`.
    """
    # Check that the treasury fee is not greater than the maximum allowed
    assert treasuryFee_ <= MAX_TREASURY_FEE, "Treasury fee too high"

    _ASSET = asset_
    asset = _ASSET.address

    _ORACLE = oracle_
    oracle = _ORACLE.address

    self.intervalSeconds = intervalSeconds_
    self.bufferSeconds = bufferSeconds_
    self.minBetAmount = minBetAmount_
    self.oracleUpdateAllowance = oracleUpdateAllowance_
    self.treasuryFee = treasuryFee_

    # The following line assigns the `owner`
    # to the `msg.sender`.
    ow.__init__()


@internal
@view
def _not_contract():
    """
    @dev Internal function to ensure the caller is
         not a contract or a proxy contract
    """
    assert not msg.sender.is_contract, "prediction: contract not allowed"
    assert msg.sender == tx.origin, "prediction: proxy contract not allowed"


@internal
@view
def _when_not_paused():
    """
    @dev Internal function to ensure the protocol is
         not paused.
    """
    assert not self.paused, "prediction: contract is paused"


@internal
@view
def _only_operator():
    """
    @dev Internal function to ensure the method is
         called only by the operator
    """
    assert msg.sender == self.operator, "prediction: contract is paused"


@internal
@view
def _bettable(epoch: uint256) -> bool:
    """
    @notice Determines whether a given round (epoch)
            is in a bettable state.
    @param epoch The epoch (round) to check.
    @return bool True if the round is bettable, False otherwise.

        A round is considered bettable if:
        - It has a valid start timestamp (non-zero).
        - It has a valid lock timestamp (non-zero).
        - The current block timestamp is between the start and lock timestamps.
    """
    r: Round = self.rounds[epoch]
    return (
        r.startTimestamp != 0 and
        r.lockTimestamp != 0 and
        block.timestamp > r.startTimestamp and
        block.timestamp < r.lockTimestamp
    )


@internal
@view
def _claimable(epoch: uint256, user: address) -> bool:
    """
    @notice Checks if the user can claim rewards for a specific epoch.
    @param epoch The epoch (round) to check.
    @param user The user's address.
    @return bool True if the user is eligible to claim, False otherwise.

    The claimable status is determined by:
    - The oracle has provided final price data (oracleCalled).
    - The user has placed a bet (amount is non-zero).
    - The user has not already claimed the reward.
    - The result of the round (whether the user's position won or lost).
    """
    
    betInfo: BetInfo = self.ledger[epoch][user]
    round: Round = self.rounds[epoch]

    # If the lock price is equal to the close price, no claims can be made.
    if round.lockPrice == round.closePrice:
        return False

    return (
        round.oracleCalled and
        betInfo.amount != 0 and
        not betInfo.claimed and
        (
            (round.closePrice > round.lockPrice and betInfo.position == Position.Bull) or
            (round.closePrice < round.lockPrice and betInfo.position == Position.Bear)
        )
    )


@internal
@view
def _refundable(epoch: uint256, user: address) -> bool:
    """
    @notice Determines whether the user is eligible for a refund for a specific epoch.
    @param epoch The epoch (round) to check.
    @param user The user's address.
    @return bool True if the user is eligible for a refund, False otherwise.

    Refundable status is determined by:
    - The oracle has not provided final price data (oracleCalled is False).
    - The user has placed a bet but not yet claimed the reward.
    - The current block timestamp is greater than the round's close timestamp plus a buffer.
    - The user has placed a bet (amount is non-zero).
    """
    
    betInfo: BetInfo = self.ledger[epoch][user]
    round: Round = self.rounds[epoch]

    # Check if the user is eligible for a refund
    return (
        not round.oracleCalled and
        not betInfo.claimed and
        block.timestamp > round.closeTimestamp + self.bufferSeconds and  
        betInfo.amount != 0
    )

@internal
@view
def _get_price_from_oracle() -> (uint80, int256):
    """
    @notice Get the latest recorded price from the oracle.
    @dev Ensures the oracle has updated within the allowed time buffer and checks
         that the oracle's round ID is valid (greater than the latest stored round ID).
    @return roundId The round ID from the oracle.
    @return price The latest price from the oracle.
    """
    least_allowed_timestamp: uint256 = block.timestamp + self.oracleUpdateAllowance

    roundId: uint80 = 0
    answer: int256 = 0
    startedAt: uint256 = 0
    updatedAt: uint256 = 0
    answeredInRound: uint80 = 0
    (roundId, answer, startedAt, updatedAt, answeredInRound) = staticcall _ORACLE.latestRoundData()

    assert block.timestamp <= least_allowed_timestamp, "prediction: oracle update exceeded max timestamp allowance"
    assert convert(roundId, uint256) > self.oracleLatestRoundId, "prediction: oracle update roundId must be larger than oracleLatestRoundId"

    return roundId, answer


@internal
def _safe_end_round(epoch: uint256, roundId: uint256, price: int256):
    """
    @notice End a specific round by locking in the closing price and oracle round ID.
    @dev This function ensures the round is locked and can only be ended after the closeTimestamp,
         but within the bufferSeconds.
    @param epoch The epoch of the round to be ended.
    @param roundId The oracle's round ID for this round.
    @param price The closing price for this round.
    """
    r: Round = self.rounds[epoch]

    assert r.lockTimestamp != 0, "prediction: can only end round after round has locked"
    assert block.timestamp >= r.closeTimestamp, "prediction: can only end round after closeTimestamp"
    assert block.timestamp <= r.closeTimestamp + self.bufferSeconds, "Can only end round within bufferSeconds"

    self.rounds[epoch].closePrice = price
    self.rounds[epoch].closeOracleId = roundId
    self.rounds[epoch].oracleCalled = True
    log EndRound(epoch, roundId, r.closePrice)


@internal
def _safe_lock_round(epoch: uint256, roundId: uint256, price: int256):
    """
    @notice Lock a specific round by setting the lock price and oracle round ID.
    @dev This function ensures that the round has started and can only be locked after the lockTimestamp,
         but within the bufferSeconds.
    @param epoch The epoch of the round to be locked.
    @param roundId The oracle's round ID for this round.
    @param price The locking price for this round.
    """
    r: Round = self.rounds[epoch]

    assert r.startTimestamp != 0, "prediction: can only lock round after round has started"
    assert block.timestamp >= r.lockTimestamp, "prediction: can only lock round after lockTimestamp"
    assert block.timestamp <= r.lockTimestamp + self.bufferSeconds, "prediction: can only lock round within bufferSeconds"

    self.rounds[epoch].closeTimestamp = block.timestamp + self.intervalSeconds
    self.rounds[epoch].lockPrice = price
    self.rounds[epoch].lockOracleId = roundId
    log LockRound(epoch, roundId, r.lockPrice)


@internal
def _start_round(epoch: uint256):
    """
    @notice Start a specific round by initializing the round's timestamps and setting the epoch.
    @dev This function sets the start, lock, and close timestamps for the new round and resets the total amount.
    @param epoch The epoch of the new round to be started.
    """
    self.rounds[epoch].startTimestamp = block.timestamp
    self.rounds[epoch].lockTimestamp = block.timestamp + self.intervalSeconds
    self.rounds[epoch].closeTimestamp = block.timestamp + (2 * self.intervalSeconds)
    self.rounds[epoch].epoch = epoch
    self.rounds[epoch].totalAmount = 0

    log StartRound(epoch)


@internal
def _safe_start_round(epoch: uint256):
    """
    @notice Start a new round by validating the status of previous rounds.
    @dev This function ensures that the genesis round has started and the n-2 round has ended before
         starting a new round.
    @param epoch The epoch of the new round to be started.
    """
    assert self.genesisStartOnce, "prediction: can only run after genesisStartRound is triggered"
    assert self.rounds[epoch - 2].closeTimestamp != 0, "prediction: can only start round after round n-2 has ended"
    assert block.timestamp >= self.rounds[epoch - 2].closeTimestamp, "prediction: can only start new round after round n-2 closeTimestamp"

    self._start_round(epoch)


@internal
def _calculate_rewards(epoch: uint256):
    """
    @notice Calculate the rewards for a specific round based on the closing and locking prices.
    @dev Rewards are calculated based on the comparison of the closing price with the locking price.
         The function handles three scenarios: bull wins, bear wins, and house wins.
    @param epoch The epoch of the round for which rewards are being calculated.
    """
    r: Round = self.rounds[epoch]
    assert r.rewardBaseCalAmount == 0 and r.rewardAmount == 0, "prediction: rewards already calculated"

    reward_base_cal_amount: uint256 = 0
    treasury_amt: uint256 = 0
    reward_amount: uint256 = 0

    # Bull wins (close price is greater than lock price)
    if r.closePrice > r.lockPrice:
        reward_base_cal_amount = r.bullAmount
        treasury_amt = (r.totalAmount * self.treasuryFee) // 10000
        reward_amount = r.totalAmount - treasury_amt

    # Bear wins (close price is less than lock price)
    elif r.closePrice < r.lockPrice:
        reward_base_cal_amount = r.bearAmount
        treasury_amt = (r.totalAmount * self.treasuryFee) // 10000
        reward_amount = r.totalAmount - treasury_amt

    # House wins (close price equals lock price)
    else:
        reward_base_cal_amount = 0
        reward_amount = 0
        treasury_amt = r.totalAmount

    self.rounds[epoch].rewardBaseCalAmount = reward_base_cal_amount
    self.rounds[epoch].rewardAmount = reward_amount

    self.treasuryAmount += treasury_amt
    log RewardsCalculated(epoch, reward_base_cal_amount, reward_amount, treasury_amt)


@external
@view
def claimable(epoch: uint256, user: address) -> bool:
    """
    @notice Checks if the user can claim rewards for a specific epoch.
    @param epoch The epoch (round) to check.
    @param user The user's address.
    @return bool True if the user is eligible to claim, False otherwise.
    """
    return self._claimable(epoch, user)


@external
@view
def refundable(epoch: uint256, user: address) -> bool:
    """
    @notice Determines whether the user is eligible for a refund for a specific epoch.
    @param epoch The epoch (round) to check.
    @param user The user's address.
    @return bool True if the user is eligible for a refund, False otherwise.
    """
    return self._refundable(epoch, user)


@external
@nonreentrant
def betBear(epoch: uint256, amount: uint256):
    """
    @notice Allows a user to place a bet on the bear position for a specific epoch.
    @param epoch The epoch in which the bet is placed.
    @param amount The amount being wagered.

        - The epoch must match the current epoch.
        - The round must be bettable.
        - The bet amount must be greater than the minimum bet amount.
        - The user can only bet once per round.
    """
    self._not_contract()
    self._when_not_paused()
    
    assert epoch == self.currentEpoch, "Bet is too early/late"
    assert self._bettable(epoch), "Round not bettable"
    assert amount >= self.minBetAmount, "Bet amount must be greater than minBetAmount"
    assert self.ledger[epoch][msg.sender].amount == 0, "Can only bet once per round"

    extcall _ASSET.transferFrom(msg.sender, self, amount)

    self.rounds[epoch].totalAmount += amount
    self.rounds[epoch].bearAmount += amount

    betInfo: BetInfo = self.ledger[epoch][msg.sender]
    betInfo.position = Position.Bear
    betInfo.amount = amount

    i: uint256 = self._userRounds[msg.sender]
    self._userRounds[msg.sender] += 1

    self.userRounds[msg.sender][i] = epoch

    log BetBear(msg.sender, epoch, amount)


@external
@nonreentrant
def betBull(epoch: uint256, amount: uint256):
    """
    @notice Allows a user to place a bet on the bear position for a specific epoch.
    @param epoch The epoch in which the bet is placed.
    @param amount The amount being wagered.
    @dev
        - The epoch must match the current epoch.
        - The round must be bettable.
        - The bet amount must be greater than the minimum bet amount.
        - The user can only bet once per round.
    """
    self._not_contract()
    self._when_not_paused()

    assert epoch == self.currentEpoch, "prediction: bet is too early/late"
    assert self._bettable(epoch), "prediction: round not bettable"
    assert amount >= self.minBetAmount, "prediction: bet amount must be greater than minBetAmount"
    assert self.ledger[epoch][msg.sender].amount == 0, "prediction: can only bet once per round"

    extcall _ASSET.transferFrom(msg.sender, self, amount)

    self.rounds[epoch].totalAmount += amount
    self.rounds[epoch].bearAmount += amount

    betInfo: BetInfo = self.ledger[epoch][msg.sender]
    betInfo.position = Position.Bull
    betInfo.amount = amount

    i: uint256 = self._userRounds[msg.sender]
    self._userRounds[msg.sender] += 1
    self.userRounds[msg.sender][i] = epoch

    log BetBull(msg.sender, epoch, amount)


@external
@nonreentrant
def claim(epochs: DynArray[uint256, 128]):
    """
    @notice Claim reward for an array of epochs
    @param epochs array of epochs
    """
    self._not_contract()
    self._when_not_paused()

    reward: uint256 = 0
    
    for epoch: uint256 in epochs:
        r: Round = self.rounds[epoch]

        assert r.startTimestamp != 0, "prediction: round has not started"
        assert r.closeTimestamp < block.timestamp, "predictioon: round has not ended"

        addedReward: uint256 = 0
        if r.oracleCalled:
            assert self._claimable(epoch, msg.sender), "prediction: not eligible for claim"
            addedReward = (self.ledger[epoch][msg.sender].amount * r.rewardAmount) // r.rewardBaseCalAmount 
        else:
            assert self._refundable(epoch, msg.sender), "prediction: not eligible for refund"
            addedReward = (self.ledger[epoch][msg.sender].amount * r.rewardAmount) // r.rewardBaseCalAmount
        
        self.ledger[epoch][msg.sender].claimed = True
        reward += addedReward

        log Claim(msg.sender, epoch, addedReward)

    if reward > 0:
        extcall _ASSET.transfer(msg.sender, reward)


@external
@nonreentrant
def executeRound():
    """
    @notice Start the next round (n), lock price for round (n-1), and end round (n-2)
    @dev Callable only by the operator. Requires that genesisStartRound and
         genesisLockRound have been triggered before this can be executed.
    """
    self._when_not_paused()
    self._only_operator()

    assert self.genesisStartOnce and self.genesisLockOnce, "prediction: an only run after genesisStartRound and genesisLockRound is triggered"

    currentRoundId: uint80 = 0
    currentPrice: int256 = 0
    currentRoundId, currentPrice = self._get_price_from_oracle()

    oracleLatestRoundId: uint256 = convert(currentRoundId, uint256)
    self.oracleLatestRoundId = oracleLatestRoundId

    self._safe_lock_round(self.currentEpoch, oracleLatestRoundId, currentPrice)
    self._safe_end_round(self.currentEpoch - 1, oracleLatestRoundId, currentPrice)

    self._calculate_rewards(self.currentEpoch - 1)

    self.currentEpoch += 1
    self._safe_start_round(self.currentEpoch)


@external
@nonreentrant
def genesisLockRound():
    """
    @notice Lock the genesis round.
    @dev This function is callable by the operator and locks the current genesis round.
         It requires that the genesis start round has been triggered and that the genesis lock round
         has not been executed yet. After locking, it starts the next round and updates the state.
    """
    assert self.genesisStartOnce, "prediction: can only run after genesisStartRound is triggered"
    assert not self.genesisLockOnce, "prediction: can only run genesisLockRound once"

    current_round_id: uint80 = 0
    current_price: int256 = 0
    current_round_id, current_price = self._get_price_from_oracle()

    oracleLatestRoundId: uint256 = convert(current_round_id, uint256)
    self.oracleLatestRoundId = oracleLatestRoundId 

    self._safe_lock_round(self.currentEpoch, oracleLatestRoundId, current_price)
    self.currentEpoch += 1

    self._start_round(self.currentEpoch)
    self.genesisLockOnce = True


@external
@nonreentrant
def genesisStartRound():
    """
    @notice Start the genesis round.
    @dev This function is callable by the operator and starts the genesis round.
         It can only be run once to initialize the first round of the protocol.
    """
    assert not self.genesisStartOnce, "prediction: an only run genesisStartRound once"
    self.currentEpoch += 1
    self._start_round(self.currentEpoch)
    self.genesisStartOnce = True


@external
@nonreentrant
def pause():
    """
    @notice Pauses the contract, triggering a stopped state.
    @dev Callable by admin or operator. Once paused, the contract enters a stopped state
         and cannot be interacted with for certain functions until unpaused.
    """
    assert not self.paused, "Contract is already paused"
    ow._check_owner()

    self.paused = True
    log Pause(self.currentEpoch)


@external
@nonreentrant
def claim_treasury():
    """
    @notice Claim all rewards stored in the treasury.
    @dev Callable by admin only. This function transfers all the treasury funds to the admin address
         and resets the treasury amount to zero.
    """
    ow._check_owner()

    current_treasury_amount: uint256 = self.treasuryAmount
    self.treasuryAmount = 0

    extcall _ASSET.transfer(ow.owner, current_treasury_amount)

    log TreasuryClaim(current_treasury_amount)


@external
@nonreentrant
def unpause():
    """
    @notice Unpauses the contract and returns to normal operation.
    @dev Callable by admin or operator. This function resets the genesis state, and once unpaused,
         the rounds need to be restarted by triggering the genesis start. 
    """
    assert self.paused, "Contract is not paused"
    ow._check_owner()

    self.genesisStartOnce = False
    self.genesisLockOnce = False
    self.paused = False

    log Unpause(self.currentEpoch)
