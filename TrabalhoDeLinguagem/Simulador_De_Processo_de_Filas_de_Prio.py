prio = []
normal = []
controle = 0

while True:
    print("MENU ")
    print("1 - Inserir Prioridade ")
    print("2 - Inserir Normal")
    print("3 - Remover ")
    print("4 - Exibir Filas")
    print("5 - SAIR")
    op = int(input("Digite a opção: "))

    if op == 1:
        print("Inserir na Prioridade")
        nome = input("Digite o nome: ")
        prio.append(nome)
        print("Inserido com sucesso")

    elif op == 2:
        print("Inserir na Normal")
        nome = input("Digite o nome:")
        normal.append(nome)
        print("Inserir com sucesso ")

    elif op == 3:
        if prio and normal and controle == 0:
            print("Removendo da Prioridade")
            prio.pop(0)
            controle = 1

        elif prio and normal and controle == 1:
            print("Removendo da Normal")
            normal.pop(0)
            controle = 0

        elif prio and not normal:
            print("Removendo da Prioridade")
            prio.pop(0)
            controle = 0

        elif not prio and normal:
            print("Removendo da Normal")
            normal.pop(0)
            controle = 0

        else:
            print("FILAS VAZIAS \n")

    elif op == 4:
        print("Prioridade: ", prio)
        print("Normal: ", normal)

    elif op == 5:
        print("TCHAU")
        break

    else:
        print("Opção Inválida")