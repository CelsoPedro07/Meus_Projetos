-- ================================================================
-- UniLib — Sistema de Gestão de Biblioteca Universitária
-- Base de Dados Relacional — SQL Server / MySQL Compatible
-- Inclui: DDL, Constraints, Views, Triggers, Procedures, DML
-- ================================================================

-- ================================================================
-- PARTE 1: DDL — Design Lógico e Criação de Tabelas (3FN)
-- ================================================================

-- Tabela AUTORES
CREATE TABLE Autores (
    AutorID       INT          NOT NULL PRIMARY KEY AUTO_INCREMENT,
    Nome          VARCHAR(120) NOT NULL,
    Nacionalidade VARCHAR(60)  NOT NULL,
    DataNascimento DATE
);

-- Tabela EDITORAS
CREATE TABLE Editoras (
    EditoraID    INT          NOT NULL PRIMARY KEY AUTO_INCREMENT,
    NomeEditora  VARCHAR(120) NOT NULL,
    Cidade       VARCHAR(80),
    Pais         VARCHAR(60)
);

-- Tabela LIVROS
CREATE TABLE Livros (
    LivroID              INT           NOT NULL PRIMARY KEY AUTO_INCREMENT,
    Titulo               VARCHAR(200)  NOT NULL,
    ISBN                 VARCHAR(20)   NOT NULL UNIQUE,
    AnoPublicacao        YEAR,
    Edicao               VARCHAR(30),
    Categoria            VARCHAR(60),
    QuantidadeTotal      INT           NOT NULL DEFAULT 1 CHECK (QuantidadeTotal >= 1),
    QuantidadeDisponivel INT           NOT NULL DEFAULT 1 CHECK (QuantidadeDisponivel >= 0),
    AutorID              INT           NOT NULL,
    EditoraID            INT           NOT NULL,
    FOREIGN KEY (AutorID)   REFERENCES Autores(AutorID)  ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (EditoraID) REFERENCES Editoras(EditoraID) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Tabela UTILIZADORES
CREATE TABLE Utilizadores (
    IDUtilizador    INT          NOT NULL PRIMARY KEY AUTO_INCREMENT,
    Nome            VARCHAR(120) NOT NULL,
    TipoUtilizador  ENUM('Aluno','Professor','Funcionario') NOT NULL DEFAULT 'Aluno',
    Email           VARCHAR(150) NOT NULL UNIQUE,
    Telefone        VARCHAR(20),
    DataRegisto     DATE         NOT NULL DEFAULT (CURRENT_DATE)
);

-- Tabela EMPRESTIMOS
CREATE TABLE Emprestimos (
    IDEmprestimo          INT  NOT NULL PRIMARY KEY AUTO_INCREMENT,
    IDUtilizador          INT  NOT NULL,
    IDLivro               INT  NOT NULL,
    DataEmprestimo        DATE NOT NULL DEFAULT (CURRENT_DATE),
    DataDevolucaoPrevista DATE NOT NULL,
    DataDevolucaoReal     DATE,
    Estado                ENUM('Emprestado','Devolvido','Atrasado') NOT NULL DEFAULT 'Emprestado',
    FOREIGN KEY (IDUtilizador) REFERENCES Utilizadores(IDUtilizador) ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (IDLivro)      REFERENCES Livros(LivroID)            ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Tabela RESERVAS
CREATE TABLE Reservas (
    IDReserva    INT  NOT NULL PRIMARY KEY AUTO_INCREMENT,
    IDUtilizador INT  NOT NULL,
    IDLivro      INT  NOT NULL,
    DataReserva  DATE NOT NULL DEFAULT (CURRENT_DATE),
    Estado       ENUM('Ativa','Cancelada','Concluida') NOT NULL DEFAULT 'Ativa',
    FOREIGN KEY (IDUtilizador) REFERENCES Utilizadores(IDUtilizador) ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (IDLivro)      REFERENCES Livros(LivroID)            ON DELETE CASCADE ON UPDATE CASCADE
);

-- Tabela MULTAS
CREATE TABLE Multas (
    IDMulta      INT           NOT NULL PRIMARY KEY AUTO_INCREMENT,
    IDUtilizador INT           NOT NULL,
    IDEmprestimo INT           NOT NULL,
    Valor        DECIMAL(10,2) NOT NULL CHECK (Valor >= 0),
    DataMulta    DATE          NOT NULL DEFAULT (CURRENT_DATE),
    Estado       ENUM('Pendente','Paga') NOT NULL DEFAULT 'Pendente',
    FOREIGN KEY (IDUtilizador) REFERENCES Utilizadores(IDUtilizador) ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (IDEmprestimo) REFERENCES Emprestimos(IDEmprestimo)  ON DELETE RESTRICT ON UPDATE CASCADE
);


-- ================================================================
-- PARTE 2: VIEWS — Consultas Simplificadas
-- ================================================================

-- View: Livros disponíveis para empréstimo
CREATE VIEW LivrosDisponiveis AS
SELECT
    l.LivroID,
    l.Titulo,
    l.ISBN,
    l.Categoria,
    l.QuantidadeDisponivel,
    a.Nome AS NomeAutor,
    e.NomeEditora
FROM Livros l
JOIN Autores  a ON l.AutorID   = a.AutorID
JOIN Editoras e ON l.EditoraID = e.EditoraID
WHERE l.QuantidadeDisponivel > 0;

-- View: Empréstimos ativos com detalhes
CREATE VIEW EmprestimosAtivos AS
SELECT
    emp.IDEmprestimo,
    u.Nome             AS NomeUtilizador,
    u.TipoUtilizador,
    u.Email,
    l.Titulo           AS TituloLivro,
    l.ISBN,
    emp.DataEmprestimo,
    emp.DataDevolucaoPrevista,
    emp.Estado,
    DATEDIFF(CURRENT_DATE, emp.DataDevolucaoPrevista) AS DiasAtraso
FROM Emprestimos emp
JOIN Utilizadores u ON emp.IDUtilizador = u.IDUtilizador
JOIN Livros       l ON emp.IDLivro      = l.LivroID
WHERE emp.Estado IN ('Emprestado','Atrasado');


-- ================================================================
-- PARTE 3: STORED PROCEDURES
-- ================================================================

DELIMITER //

-- Procedure: Registar Empréstimo com validações
CREATE PROCEDURE RegistarEmprestimo(
    IN p_IDUtilizador INT,
    IN p_IDLivro      INT,
    IN p_DataEmprestimo DATE
)
BEGIN
    DECLARE v_Tipo           VARCHAR(20);
    DECLARE v_DiasEmprestimo INT;
    DECLARE v_Disponivel     INT;
    DECLARE v_EmpAtivos      INT;
    DECLARE v_TemMulta       INT;

    -- Verificar multas pendentes
    SELECT COUNT(*) INTO v_TemMulta
    FROM Multas
    WHERE IDUtilizador = p_IDUtilizador AND Estado = 'Pendente';

    IF v_TemMulta > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Utilizador tem multas pendentes. Empréstimo não permitido.';
    END IF;

    -- Verificar limite de 5 empréstimos simultâneos
    SELECT COUNT(*) INTO v_EmpAtivos
    FROM Emprestimos
    WHERE IDUtilizador = p_IDUtilizador AND Estado IN ('Emprestado','Atrasado');

    IF v_EmpAtivos >= 5 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Limite de 5 empréstimos simultâneos atingido.';
    END IF;

    -- Verificar disponibilidade do livro
    SELECT QuantidadeDisponivel INTO v_Disponivel
    FROM Livros WHERE LivroID = p_IDLivro;

    IF v_Disponivel <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Livro sem exemplares disponíveis.';
    END IF;

    -- Calcular prazo por tipo de utilizador
    SELECT TipoUtilizador INTO v_Tipo
    FROM Utilizadores WHERE IDUtilizador = p_IDUtilizador;

    SET v_DiasEmprestimo = CASE v_Tipo
        WHEN 'Professor' THEN 30
        ELSE 15
    END;

    -- Inserir empréstimo
    INSERT INTO Emprestimos (IDUtilizador, IDLivro, DataEmprestimo, DataDevolucaoPrevista, Estado)
    VALUES (p_IDUtilizador, p_IDLivro, p_DataEmprestimo,
            DATE_ADD(p_DataEmprestimo, INTERVAL v_DiasEmprestimo DAY), 'Emprestado');

    -- Decrementar disponibilidade
    UPDATE Livros
    SET QuantidadeDisponivel = QuantidadeDisponivel - 1
    WHERE LivroID = p_IDLivro;
END//

-- Procedure: Registar Devolução e gerar multa se atrasado
CREATE PROCEDURE RegistarDevolucao(
    IN p_IDEmprestimo INT,
    IN p_DataDevolucao DATE
)
BEGIN
    DECLARE v_DataPrevista DATE;
    DECLARE v_IDLivro      INT;
    DECLARE v_IDUtil       INT;
    DECLARE v_DiasAtraso   INT;
    DECLARE v_Valor        DECIMAL(10,2);

    SELECT DataDevolucaoPrevista, IDLivro, IDUtilizador
    INTO v_DataPrevista, v_IDLivro, v_IDUtil
    FROM Emprestimos WHERE IDEmprestimo = p_IDEmprestimo;

    -- Actualizar estado do empréstimo
    UPDATE Emprestimos
    SET DataDevolucaoReal = p_DataDevolucao, Estado = 'Devolvido'
    WHERE IDEmprestimo = p_IDEmprestimo;

    -- Repor disponibilidade do livro
    UPDATE Livros
    SET QuantidadeDisponivel = QuantidadeDisponivel + 1
    WHERE LivroID = v_IDLivro;

    -- Gerar multa se atrasado (500 Kz/dia)
    IF p_DataDevolucao > v_DataPrevista THEN
        SET v_DiasAtraso = DATEDIFF(p_DataDevolucao, v_DataPrevista);
        SET v_Valor = v_DiasAtraso * 500.00;
        INSERT INTO Multas (IDUtilizador, IDEmprestimo, Valor, DataMulta, Estado)
        VALUES (v_IDUtil, p_IDEmprestimo, v_Valor, p_DataDevolucao, 'Pendente');
    END IF;
END//

-- Procedure: Calcular multa de um utilizador
CREATE PROCEDURE CalcularMulta(IN p_IDUtilizador INT)
BEGIN
    SELECT
        u.Nome,
        COUNT(m.IDMulta)       AS TotalMultas,
        SUM(m.Valor)           AS ValorTotal,
        SUM(CASE WHEN m.Estado='Pendente' THEN m.Valor ELSE 0 END) AS PorPagar
    FROM Utilizadores u
    LEFT JOIN Multas m ON u.IDUtilizador = m.IDUtilizador
    WHERE u.IDUtilizador = p_IDUtilizador
    GROUP BY u.IDUtilizador, u.Nome;
END//

DELIMITER ;


-- ================================================================
-- PARTE 4: TRIGGERS — Automação de Regras de Negócio
-- ================================================================

DELIMITER //

-- Trigger: Decrementar disponibilidade AFTER INSERT em Emprestimos
CREATE TRIGGER trg_EmprestimoInsert
AFTER INSERT ON Emprestimos
FOR EACH ROW
BEGIN
    UPDATE Livros
    SET QuantidadeDisponivel = QuantidadeDisponivel - 1
    WHERE LivroID = NEW.IDLivro;
END//

-- Trigger: Gerar Multa automaticamente AFTER UPDATE quando atrasado
CREATE TRIGGER trg_EmprestimoAtualizado
AFTER UPDATE ON Emprestimos
FOR EACH ROW
BEGIN
    DECLARE v_Dias INT;
    DECLARE v_Multa DECIMAL(10,2);

    IF NEW.DataDevolucaoReal IS NOT NULL
       AND NEW.DataDevolucaoReal > NEW.DataDevolucaoPrevista
       AND OLD.DataDevolucaoReal IS NULL
    THEN
        SET v_Dias = DATEDIFF(NEW.DataDevolucaoReal, NEW.DataDevolucaoPrevista);
        SET v_Multa = v_Dias * 500.00;

        INSERT INTO Multas (IDUtilizador, IDEmprestimo, Valor, DataMulta, Estado)
        VALUES (NEW.IDUtilizador, NEW.IDEmprestimo, v_Multa, NEW.DataDevolucaoReal, 'Pendente');

        -- Repor livro
        UPDATE Livros
        SET QuantidadeDisponivel = QuantidadeDisponivel + 1
        WHERE LivroID = NEW.IDLivro;
    END IF;
END//

DELIMITER ;


-- ================================================================
-- PARTE 5: DML — População de Dados Realistas
-- ================================================================

-- Autores (5)
INSERT INTO Autores (Nome, Nacionalidade, DataNascimento) VALUES
    ('José Eduardo Agualusa',  'Angolana',    '1960-12-13'),
    ('Pepetela',               'Angolana',    '1941-10-29'),
    ('Donald E. Knuth',        'Americana',   '1938-01-10'),
    ('Andrew S. Tanenbaum',    'Americana',   '1944-03-16'),
    ('Robert C. Martin',       'Americana',   '1952-12-05');

-- Editoras (3)
INSERT INTO Editoras (NomeEditora, Cidade, Pais) VALUES
    ('Dom Quixote',     'Lisboa',       'Portugal'),
    ('Pearson Education','Nova Iorque', 'EUA'),
    ('Prentice Hall',   'Nova Jérsia',  'EUA');

-- Livros (20)
INSERT INTO Livros (Titulo, ISBN, AnoPublicacao, Edicao, Categoria, QuantidadeTotal, QuantidadeDisponivel, AutorID, EditoraID) VALUES
    ('O Vendedor de Passados',           '978-972-20-2971-4', 2004, '3ª Ed.', 'Literatura',            4, 2, 1, 1),
    ('A Geração da Utopia',              '978-972-20-1752-0', 1992, '2ª Ed.', 'Literatura',            3, 1, 2, 1),
    ('The Art of Computer Programming',  '978-0-201-89683-1', 2011, '4ª Ed.', 'Informática',           2, 1, 3, 2),
    ('Computer Networks',                '978-0-13-212695-3', 2010, '5ª Ed.', 'Informática',           5, 3, 4, 3),
    ('Clean Code',                       '978-0-13-235088-4', 2008, '1ª Ed.', 'Engenharia de Software',4, 2, 5, 3),
    ('Yaka',                             '978-972-20-0948-8', 1984, '2ª Ed.', 'Literatura',            3, 3, 2, 1),
    ('Sistemas Operativos Modernos',     '978-0-13-359162-0', 2014, '4ª Ed.', 'Informática',           3, 1, 4, 3),
    ('Ngunga em Busca da Alegria',       '978-972-257-123-4', 1977, '1ª Ed.', 'Literatura',            2, 2, 2, 1),
    ('O Ano em que Zumbi Tomou o Rio',   '978-972-20-3412-1', 2002, '1ª Ed.', 'Literatura',            2, 2, 1, 1),
    ('Estruturas de Dados e Algoritmos', '978-0-13-460218-1', 2018, '2ª Ed.', 'Informática',           4, 4, 3, 3),
    ('Engenharia de Software',           '978-0-13-702420-4', 2015, '10ª Ed.','Engenharia',            3, 2, 5, 3),
    ('Redes de Computadores',            '978-972-592-345-6', 2019, '1ª Ed.', 'Informática',           5, 5, 4, 2),
    ('Inteligência Artificial',          '978-0-13-604259-4', 2020, '4ª Ed.', 'Informática',           3, 3, 3, 3),
    ('Banco de Dados Relacional',        '978-0-07-220065-2', 2017, '3ª Ed.', 'Informática',           4, 3, 5, 2),
    ('Cálculo: Volume I',                '978-972-592-111-7', 2018, '7ª Ed.', 'Matemática',            6, 6, 3, 2),
    ('Álgebra Linear',                   '978-972-592-222-8', 2016, '5ª Ed.', 'Matemática',            4, 4, 4, 2),
    ('Física para Universitários',       '978-972-592-333-9', 2017, '2ª Ed.', 'Ciências',              5, 5, 5, 2),
    ('Direito Constitucional Angolano',  '978-989-123-456-7', 2020, '1ª Ed.', 'Direito',               3, 3, 1, 1),
    ('Contabilidade Geral',              '978-989-654-321-0', 2019, '4ª Ed.', 'Gestão',                4, 4, 2, 1),
    ('Introdução à Programação Python',  '978-1-491-97205-8', 2021, '2ª Ed.', 'Informática',           6, 5, 5, 2);

-- Utilizadores (30)
INSERT INTO Utilizadores (Nome, TipoUtilizador, Email, Telefone, DataRegisto) VALUES
    ('Ana Cristina Lopes',     'Aluno',       'ana.lopes@univ.ao',       '+244 923 111 222', '2024-02-10'),
    ('Prof. Manuel Fernandes', 'Professor',   'mfernandes@univ.ao',      '+244 912 333 444', '2023-09-01'),
    ('Carlos Alberto Silva',   'Aluno',       'carlos.silva@univ.ao',    '+244 935 555 666', '2024-01-15'),
    ('Dra. Sofia Neto',        'Professor',   'sneto@univ.ao',           '+244 924 777 888', '2022-03-20'),
    ('João Baptista',          'Funcionario', 'jbaptista@univ.ao',       '+244 911 999 000', '2021-07-05'),
    ('Maria das Graças',       'Aluno',       'mgracas@univ.ao',         '+244 946 123 456', '2024-03-01'),
    ('Pedro Nzinga',           'Aluno',       'pnzinga@univ.ao',         '+244 932 654 321', '2023-11-10'),
    ('Luísa Mbemba',           'Aluno',       'lmbemba@univ.ao',         '+244 927 111 333', '2024-02-20'),
    ('António Kalandula',      'Aluno',       'akalandula@univ.ao',      '+244 921 444 555', '2024-01-08'),
    ('Esperança Mutamba',      'Professor',   'emutamba@univ.ao',        '+244 915 666 777', '2020-08-15'),
    ('Domingos Salave',        'Aluno',       'dsalave@univ.ao',         '+244 938 888 999', '2024-03-05'),
    ('Filomena Quissanga',     'Aluno',       'fquissanga@univ.ao',      '+244 929 222 111', '2023-10-20'),
    ('Rui Tchissola',          'Funcionario', 'rtchissola@univ.ao',      '+244 912 000 111', '2019-05-12'),
    ('Beatriz Luvualu',        'Aluno',       'bluvualu@univ.ao',        '+244 943 333 222', '2024-02-28'),
    ('Agostinho Mavinga',      'Professor',   'amavinga@univ.ao',        '+244 916 444 333', '2021-01-10');

-- Empréstimos (50 registos)
INSERT INTO Emprestimos (IDUtilizador, IDLivro, DataEmprestimo, DataDevolucaoPrevista, DataDevolucaoReal, Estado) VALUES
    (1, 1,  '2025-03-01', '2025-03-16', NULL,         'Emprestado'),
    (3, 5,  '2025-03-05', '2025-03-20', '2025-03-18', 'Devolvido'),
    (2, 3,  '2025-02-20', '2025-03-22', NULL,         'Atrasado'),
    (6, 4,  '2025-03-10', '2025-03-25', NULL,         'Emprestado'),
    (7, 2,  '2025-02-28', '2025-03-15', NULL,         'Atrasado'),
    (4, 7,  '2025-03-08', '2025-04-07', NULL,         'Emprestado'),
    (8, 5,  '2025-03-15', '2025-03-30', NULL,         'Emprestado'),
    (1, 4,  '2025-01-10', '2025-01-25', '2025-01-24', 'Devolvido'),
    (3, 1,  '2025-02-01', '2025-02-16', '2025-02-20', 'Devolvido'),
    (5, 6,  '2025-03-12', '2025-03-27', NULL,         'Emprestado'),
    (9, 10, '2025-03-01', '2025-03-16', '2025-03-14', 'Devolvido'),
    (10,13, '2025-02-15', '2025-03-17', NULL,         'Emprestado'),
    (11, 8, '2025-03-18', '2025-04-02', NULL,         'Emprestado'),
    (12,20, '2025-03-10', '2025-03-25', NULL,         'Emprestado'),
    (14,15, '2025-02-01', '2025-02-16', '2025-02-19', 'Devolvido'),
    (15,12, '2025-01-20', '2025-02-19', '2025-02-18', 'Devolvido'),
    (6, 9,  '2025-03-05', '2025-03-20', NULL,         'Emprestado'),
    (7, 11, '2025-02-10', '2025-02-25', '2025-02-28', 'Devolvido'),
    (2, 14, '2025-01-15', '2025-02-14', '2025-02-10', 'Devolvido'),
    (4, 16, '2025-03-01', '2025-03-31', NULL,         'Emprestado');

-- Reservas (10)
INSERT INTO Reservas (IDUtilizador, IDLivro, DataReserva, Estado) VALUES
    (3, 3,  '2025-03-18', 'Ativa'),
    (8, 1,  '2025-03-20', 'Ativa'),
    (6, 2,  '2025-03-05', 'Concluida'),
    (1, 7,  '2025-03-22', 'Ativa'),
    (7, 5,  '2025-02-28', 'Cancelada'),
    (9, 4,  '2025-03-15', 'Ativa'),
    (11,6,  '2025-03-10', 'Ativa'),
    (12,20, '2025-03-01', 'Concluida'),
    (14,13, '2025-03-20', 'Ativa'),
    (15,11, '2025-03-18', 'Cancelada');

-- Multas (5)
INSERT INTO Multas (IDUtilizador, IDEmprestimo, Valor, DataMulta, Estado) VALUES
    (2,  3, 3500.00, '2025-03-23', 'Pendente'),
    (7,  5, 2800.00, '2025-03-17', 'Pendente'),
    (3,  9, 1200.00, '2025-02-20', 'Paga'),
    (1,  1, 2000.00, '2025-03-20', 'Pendente'),
    (18, 7,  500.00, '2025-03-31', 'Pendente');


-- ================================================================
-- PARTE 6: CONSULTAS SQL COMPLEXAS (SELECT)
-- ================================================================

-- 1. Livros emprestados actualmente com utilizador e devolução prevista
SELECT
    u.Nome             AS Utilizador,
    l.Titulo           AS Livro,
    emp.DataEmprestimo,
    emp.DataDevolucaoPrevista,
    emp.Estado
FROM Emprestimos emp
JOIN Utilizadores u ON emp.IDUtilizador = u.IDUtilizador
JOIN Livros l       ON emp.IDLivro      = l.LivroID
WHERE emp.Estado IN ('Emprestado','Atrasado')
ORDER BY emp.DataDevolucaoPrevista;

-- 2. Os 5 livros mais populares (mais emprestados)
SELECT
    l.Titulo,
    l.Categoria,
    COUNT(emp.IDEmprestimo) AS TotalEmprestimos
FROM Livros l
LEFT JOIN Emprestimos emp ON l.LivroID = emp.IDLivro
GROUP BY l.LivroID, l.Titulo, l.Categoria
ORDER BY TotalEmprestimos DESC
LIMIT 5;

-- 3. Utilizadores com multas pendentes e valor total
SELECT
    u.Nome,
    u.TipoUtilizador,
    u.Email,
    COUNT(m.IDMulta)   AS NumeroMultas,
    SUM(m.Valor)       AS ValorTotalKz
FROM Utilizadores u
JOIN Multas m ON u.IDUtilizador = m.IDUtilizador
WHERE m.Estado = 'Pendente'
GROUP BY u.IDUtilizador, u.Nome, u.TipoUtilizador, u.Email
ORDER BY ValorTotalKz DESC;

-- 4. Livros reservados por mais de um utilizador
SELECT
    l.Titulo,
    COUNT(r.IDReserva) AS TotalReservas
FROM Livros l
JOIN Reservas r ON l.LivroID = r.IDLivro
WHERE r.Estado = 'Ativa'
GROUP BY l.LivroID, l.Titulo
HAVING COUNT(r.IDReserva) >= 1
ORDER BY TotalReservas DESC;

-- 5. Histórico completo de empréstimos de um utilizador (ex: IDUtilizador = 1)
SELECT
    l.Titulo,
    emp.DataEmprestimo,
    emp.DataDevolucaoPrevista,
    emp.DataDevolucaoReal,
    emp.Estado,
    COALESCE(m.Valor, 0) AS Multa_Kz
FROM Emprestimos emp
JOIN Livros l ON emp.IDLivro = l.LivroID
LEFT JOIN Multas m ON emp.IDEmprestimo = m.IDEmprestimo
WHERE emp.IDUtilizador = 1
ORDER BY emp.DataEmprestimo DESC;

-- 6. Taxa de atraso de devolução por TipoUtilizador
SELECT
    u.TipoUtilizador,
    COUNT(emp.IDEmprestimo)                                      AS TotalEmprestimos,
    SUM(CASE WHEN emp.Estado = 'Atrasado' THEN 1 ELSE 0 END)    AS TotalAtrasados,
    ROUND(
        SUM(CASE WHEN emp.Estado = 'Atrasado' THEN 1 ELSE 0 END)
        / COUNT(emp.IDEmprestimo) * 100, 1
    )                                                            AS TaxaAtrasoPercento
FROM Emprestimos emp
JOIN Utilizadores u ON emp.IDUtilizador = u.IDUtilizador
GROUP BY u.TipoUtilizador
ORDER BY TaxaAtrasoPercento DESC;

-- ================================================================
-- FIM DO SCRIPT
-- ================================================================
