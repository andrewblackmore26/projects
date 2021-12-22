let player = {
    name: "Per",
    chips: 200
}

let cards = []
let dealer_cards = []
let sum = 0
let dealer_sum = 0
let hasBlackJack = false
let isAlive = false
let message = ""
let messageEl = document.getElementById("message-el")
let sumEl = document.getElementById("sum-el")
let dealerSumEl = document.getElementById("dealer_sum_el")
let cardsEl = document.getElementById("cards-el")
let playerEl = document.getElementById("player-el")
let dealerCardsEl = document.getElementById("dealer_cards_el")
const doneEl = document.getElementById("done-el")

playerEl.textContent = player.name + ": $" + player.chips

function getRandomCard() {
    let randomNumber = Math.floor( Math.random()*13 ) + 1
    if (randomNumber > 10) {
        return 10
    } else if (randomNumber === 1) {
        return 11
    } else {
        return randomNumber
    }
}

function startGame() {
    isAlive = true
    hasBlackJack = false
    let firstCard = getRandomCard()
    let secondCard = getRandomCard()
    let dealer_first = getRandomCard()
    let dealer_second = getRandomCard()
    cards = [firstCard, secondCard]
    dealer_cards = [dealer_first, dealer_second]
    dealer_sum = dealer_first + dealer_second
    sum = firstCard + secondCard
    renderGame()
}

function renderGame() {
    cardsEl.textContent = "Cards: "
    for (let i = 0; i < cards.length; i++) {
        cardsEl.textContent += cards[i] + " "
    }
    dealerCardsEl.textContent = "Dealer Cards: "
    for (let i = 0; i < dealer_cards.length; i++) {
        dealerCardsEl.textContent += dealer_cards[i] + " "
    }
    dealerSumEl.textContent = "Dealer Sum: " + dealer_sum
    sumEl.textContent = "Sum: " + sum
    if (sum <= 20) {
        message = "Do you want to draw a new card?"
    } else if (sum === 21) {
        message = "You've got Blackjack!"
        hasBlackJack = true
    } else {
        message = "You're out of the game!"
        isAlive = false
    }
    if (isAlive == false) {
        message += notAlive()
    }
    messageEl.textContent = message
}

function notAlive() {
    let string = ""
    if (sum > 21) {
        string += " You lose!!"
    } else if (dealer_sum > 21) {
        string += " You win!!"
    } else if (sum > dealer_sum) {
        string += " You win!!"
    } else if (sum === dealer_sum) {
        string += " You draw."
    } else {
        string += " You lose!"
    }
    return string
}

doneEl.addEventListener("click", function() {
    let newCard = getRandomCard()
    if (dealer_sum < sum && dealer_sum < 21) {
        dealer_cards.push(newCard)
        dealer_sum += newCard
    }
    isAlive = false
    renderGame()
})


function newCard() {
    console.log("new card called")
    if (isAlive === true && hasBlackJack === false) {
        let card = getRandomCard()
        sum += card
        cards.push(card)       
    } else  {
        sumEl.textContent = "NEWCARD ERROR"
    }
    renderGame()
}
