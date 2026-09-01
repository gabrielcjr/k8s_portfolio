const express = require('express')
const app = express()
const port = 80

app.get('/', (req,res) => {
    res.send('<h1>Hello Logical Curve</h1>')
})

app.listen(port, ()=> {
    console.log('Rodando na porta ' + port)
})