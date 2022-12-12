// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IERC20 {

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}


contract TokenSwap is ReentrancyGuard {
    
    //create state variables
    bytes32 public constant PAUSER_ROLE = keccak256("DAO_ROLE");
    IERC20 public lt;
    IERC20 public usdt;
    address public lt_token;
    address public usdt_token;
    uint256 public fees;

    struct Swap {
        address tokenIn;           // Address of the token contract to be sold
        address tokenOut;          // Address of the token contract to be exchnaged
        uint256 tokenInAmount;        // Number of tokens requested
        uint256 tokenOutMinAmount;        // Number of tokens requested
        address seller;          // Seller's address (holder of tokens In)
        uint256 timeLock;
    }

    struct P2PSwap {
        address tokenIn;           // Address of the token contract to be sold
        address tokenOut;          // Address of the token contract to be exchnaged
        uint256 tokenInAmount;        // Number of tokens requested
        uint256 tokenOutMinAmount;        // Number of tokens requested
        address seller;          // Seller's address (holder of tokens In)
        address trader;         // Trader's address (holder of tokens Out)
        uint256 timeLock;
        bytes32 secretLock;
        bytes secretKey;
    }

    enum SwapState {
        INVALID,
        OPEN,
        COMPLETED,
        EXPIRED
    }

    mapping (bytes32 => Swap) public swaps;
    mapping (bytes32 => P2PSwap) public p2pswaps;
    mapping (bytes32 => SwapState) public swapStates;


    event Open(bytes32 _swapID, address _seller, uint256 _timeLock);
    event Complete(bytes32 _swapID, address _trader, uint256 _tokenInAmount, uint256 _tokenOutAmount);
    event Expire(bytes32 _swapID);
    event Close(bytes32 _swapID, bytes _secretKey);
    
    constructor() {
        fees = 25;
    }

    // setContractAddresses(address _lt_address, address _usdt_address) public onlyRole(DAO_ROLE) {
    //     lt_token = IERC20(_lt_address);
    //     usdt_token = IERC20(_usdt_address);
    // }

    function createSwap( bytes32 _swapID, address _tokenIn, uint256 _tokenInAmount, address _tokenOut, uint256 _tokenOutMinAmount, uint256 _timeLock) public {
        require(swapStates[_swapID] == SwapState.INVALID, "");
        require(_timeLock > block.timestamp,"Time in the past");
        
        // Has the seller approved the tokens?
        IERC20 inToken = IERC20(_tokenIn);
        require(inToken.allowance(msg.sender, address(this)) >= _tokenInAmount, "Not enough allowance");
        require(inToken.transferFrom(msg.sender, address(this), _tokenInAmount));

        // Store the details of the swap.
        Swap memory swap = Swap({
            timeLock: _timeLock,
            tokenInAmount: _tokenInAmount,
            tokenIn: _tokenIn,
            tokenOutMinAmount: _tokenOutMinAmount,
            tokenOut: _tokenOut,
            seller: msg.sender
        });

        swaps[_swapID] = swap;
        swapStates[_swapID] = SwapState.OPEN;
        emit Open(_swapID, msg.sender, _timeLock);       
    }
        
        //this function will allow 2 people to trade 2 tokens as the same time (atomic) and swap them between accounts
        //Bob holds token 1 and needs to send to alice
        //Alice holds token 2 and needs to send to Bob
        //this allows them to swap an amount of both tokens at the same time
        
        //*** Important ***
        //this contract needs an allowance to send tokens at token 1 and token 2 that is owned by owner 1 and owner 2
        
    function acceptSwap(bytes32 _swapID, uint256 _tokenOutAmount) public nonReentrant {
        require(swapStates[_swapID] == SwapState.OPEN, "Swap not open");
        
        Swap memory swap = swaps[_swapID];
        require(swap.timeLock > block.timestamp,"Swap expired");
        require(swap.tokenOutMinAmount <= _tokenOutAmount, "Insuffiecient amount");        
        // Has the seller approved the tokens?
        IERC20 inToken = IERC20(swap.tokenIn);
        IERC20 outToken = IERC20(swap.tokenOut);
        require(outToken.allowance(msg.sender, address(this)) >= (_tokenOutAmount + (_tokenOutAmount * fees /10000)), "Not enough allowance");
        
        //transfer TokenSwap
        //token1, owner1, amount 1 -> owner2.  needs to be in same order as function
        bool sent = outToken.transferFrom(msg.sender, swap.seller, _tokenOutAmount);
        require(sent, "Token transfer failed");
        sent = inToken.transfer( msg.sender, swap.tokenInAmount);
        require(sent, "Token transfer failed");

        swapStates[_swapID] = SwapState.COMPLETED;

        emit Complete(_swapID, msg.sender, swap.tokenInAmount, _tokenOutAmount);
            
    }

    function refundSwap(bytes32 _swapID) public {
        require(swapStates[_swapID] == SwapState.OPEN, "Swap should be Closed");
        Swap memory swap = swaps[_swapID];
        require(swap.timeLock < block.timestamp,"Swap has not expired");
        require(swap.seller == msg.sender, "Not authorized");
        IERC20 inToken = IERC20(swap.tokenIn);
        inToken.transfer(swap.seller, swap.tokenInAmount);
        swapStates[_swapID] = SwapState.EXPIRED;
    }

    function createP2PSwap( bytes32 _swapID, address _tokenIn, uint256 _tokenInAmount, address _tokenOut, uint256 _tokenOutMinAmount, address _trader, uint256 _timeLock, bytes32 _secretLock) public {
        require(swapStates[_swapID] == SwapState.INVALID, "");
        require(_timeLock > block.timestamp,"Time in the past");
        
        // Has the seller approved the tokens?
        IERC20 inToken = IERC20(_tokenIn);
        require(inToken.allowance(msg.sender, address(this)) >= _tokenInAmount, "Not enough allowance");
        require(inToken.transferFrom(msg.sender, address(this), _tokenInAmount));

        // Store the details of the swap.
        P2PSwap memory swap = P2PSwap({
            timeLock: _timeLock,
            tokenInAmount: _tokenInAmount,
            tokenIn: _tokenIn,
            tokenOutMinAmount: _tokenOutMinAmount,
            tokenOut: _tokenOut,
            seller: msg.sender,
            trader: _trader,
            secretLock: _secretLock,
            secretKey: new bytes(0)
        });

        p2pswaps[_swapID] = swap;
        swapStates[_swapID] = SwapState.OPEN;
        emit Open(_swapID, msg.sender, _timeLock);       
    }
        
        //this function will allow 2 people to trade 2 tokens as the same time (atomic) and swap them between accounts
        //Bob holds token 1 and needs to send to alice
        //Alice holds token 2 and needs to send to Bob
        //this allows them to swap an amount of both tokens at the same time
        
        //*** Important ***
        //this contract needs an allowance to send tokens at token 1 and token 2 that is owned by owner 1 and owner 2
        
    function acceptP2PSwap(bytes32 _swapID, uint256 _tokenOutAmount, bytes memory _secretKey) public nonReentrant {
        require(swapStates[_swapID] == SwapState.OPEN, "Swap not open");
        
        P2PSwap memory swap = p2pswaps[_swapID];
        require(swap.timeLock > block.timestamp,"Swap expired");
        require(swap.secretLock == keccak256(_secretKey));
        require(swap.tokenOutMinAmount <= _tokenOutAmount, "Insuffiecient amount");        
        // Has the seller approved the tokens?
        IERC20 inToken = IERC20(swap.tokenIn);
        IERC20 outToken = IERC20(swap.tokenOut);
        require(outToken.allowance(msg.sender, address(this)) >= (_tokenOutAmount + (_tokenOutAmount * fees /10000)), "Not enough allowance");
        
        //transfer TokenSwap
        //token1, owner1, amount 1 -> owner2.  needs to be in same order as function
        bool sent = outToken.transferFrom( msg.sender, swap.seller, _tokenOutAmount);
        require(sent, "Token transfer failed");
        sent = inToken.transfer( swap.trader, swap.tokenInAmount);
        require(sent, "Token transfer failed");

        swapStates[_swapID] = SwapState.COMPLETED;

        emit Complete(_swapID, msg.sender, swap.tokenInAmount, _tokenOutAmount);
            
    }

    function refundP2PSwap(bytes32 _swapID) public {
        require(swapStates[_swapID] == SwapState.OPEN, "Swap should be Closed");
        Swap memory swap = swaps[_swapID];
        require(swap.timeLock < block.timestamp,"Swap has not expired");
        require(swap.seller == msg.sender, "Not authorized");
        IERC20 inToken = IERC20(swap.tokenIn);
        inToken.transfer(swap.seller, swap.tokenInAmount);
        swapStates[_swapID] = SwapState.EXPIRED;
    }

    function withdraw(address withdrawAddress) public onlyOwner nonReentrant {
        uint256 amount = address(this).balance;
        payable(withdrawAddress).call{value: amount}('');
    }

    function withdrawTokens(address _tokenContract, address withdrawAddress) external onlyOwner nonReentrant {
        IERC20 tokenContract = IERC20(_tokenContract);

        // transfer the token from address of Catbotica address
        uint256 _amount = tokenContract.balanceOf(address(this));
        tokenContract.transfer(withdrawAddress, _amount);

    }

}
