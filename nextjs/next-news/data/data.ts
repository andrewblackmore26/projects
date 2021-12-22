export let data: {
    name: string,
    id: number,
    img: string,
    special: number,
    attack: number,
    defence: number
}[] = [
    {
        name: "Gang gang",
        id: 0,
        img: "./clean_manyBruces.png",
        special: 0, //For every unit enemy has
        attack: 4,
        defence: 4
    },
    {
        name: "Forbidden Hookup",
        id: 1,
        img: "./clean_mwangBlack.png",
        special: 1, //Curse: user loses 2hp per turn, enemy loses 5hp
        attack: 0,
        defence: 0
    },
    {
        name: "CEO of China",
        id: 2,
        img: "./clean_businessMwang.png",
        special: 2, //Use an extra card for that turn
        attack: 2,
        defence: 3
    }
]