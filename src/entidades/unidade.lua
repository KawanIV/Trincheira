local Unidade = {}

function Unidade.nova(x, y, faccao)
    return {
        x = x, y = y,
        hp = 10,
        faccao = faccao,
        jaAgiu = false
    }
end

return Unidade