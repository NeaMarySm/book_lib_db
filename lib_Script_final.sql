USE book_lib;

-- выборки

-- 1. список авторов с количеством книг

SELECT 
	concat(a.firstname,' ', a.lastname) author,
	count(*) total_books
FROM 
	authors a 
LEFT JOIN 
	books_authors ba ON a.id = ba.author_id 
LEFT JOIN 
	books b ON ba.book_id = b.id
GROUP BY 
	a.id
ORDER BY
	a.lastname;

-- 2. топ-100 книг по рейтингу

SELECT 
	b.name,
	avg(rating) rating,
	count(*) rating_num -- количество оценок
FROM 
	books b 
LEFT JOIN 
	feedback f ON b.id = f.book_id
GROUP BY 
	b.id
ORDER BY 
	rating DESC, rating_num DESC 
LIMIT 100;

-- 3. список книг для определенного автора по рейтингу
SELECT 
	b.name book,
	concat(a.firstname, ' ', a.lastname) author,
	avg(f.rating) rating
FROM 
	books b 
JOIN 
	books_authors ba ON b.id = ba.book_id
JOIN 
	authors a ON ba.author_id = a.id
JOIN 
	feedback f ON b.id = f.book_id 
WHERE a.id = 15 -- выборка для автора с id=15
GROUP BY b.id
ORDER BY rating DESC;

-- 4. 50 самых читающих пользователей по таблице статистики и таблице книги пользователей
SELECT 
	u.id,
	CONCAT(u.firstname,' ', u.lastname ) `user`,
	us.books_count, -- количество книг, которые пользователь читал
	COUNT(ub.book_id) books_finished	-- количество книг, которые дочитал до конца 
FROM 
	users_stats us  
JOIN users u ON u.id = us.user_id 
JOIN user_books ub ON u.id = ub.user_id 
WHERE ub.status = 'finished'
GROUP BY ub.user_id 
ORDER BY 
	books_count DESC, books_finished DESC 
LIMIT 50;


-- 5. список пользователей и их подписок, null - пользователь без подписки
SELECT 
	u.id,
	u.email,
	s.name subscription
FROM 
	users u
LEFT JOIN 
	subscription_plans sp  ON u.subscription_plan_id = sp.id 
LEFT JOIN subscriptions s ON sp.subscription_id = s.id
ORDER BY s.name;

-- 6.книги с наибольшим количеством отзывов и их рейтинг

SELECT 
 	b.name,
 	count(*) cnt,
 	AVG(rating) rating 
FROM 
	feedback f
JOIN 
	books b ON f.book_id = b.id
WHERE 
	body IS NOT NULL
GROUP BY 
	book_id
ORDER BY cnt DESC, rating DESC  
LIMIT 20;

-- процедуры

-- 1. поиск книг по жанру
DROP PROCEDURE IF EXISTS books_by_genre;
delimiter //
CREATE PROCEDURE books_by_genre (IN genre varchar(255))
BEGIN 
	
	DECLARE find_genre_id BIGINT;
	SET find_genre_id = (
		SELECT id 
		FROM genres
		WHERE name = genre
	);

	SELECT 
		b.name book
	FROM 
		books b 
	JOIN 
		books_genres bg ON b.id = bg.book_id 
	JOIN 
		genres g ON bg.genre_id = g.id 
	WHERE 
		g.id = find_genre_id; 
END//

delimiter ;

CALL books_by_genre('fantasy');


-- 2. рекомендации пользователям
	-- выбираем пользователей со схожими вкусами на основании совпадения рейтинга книги с заданным пользователем
	-- выбираем книги этих пользователей и в случайном порядке выводим 10шт
	-- в данном случае в выборку попадут не только прочитанные книги, но и книги, 
	-- которые в принципе есть на полках у пользователей со схожими вкусами, т.е. книги заинтересовавшие их

DROP PROCEDURE IF EXISTS recommendations;

delimiter //
CREATE PROCEDURE recommendations (IN for_user_id INT)
  BEGIN 

	SELECT ub.book_id,
			b.name
	FROM user_books ub 
	JOIN books b ON ub.book_id = b.id
	WHERE ub.user_id IN (
		SELECT 
			f2.user_id -- пользователи со схожими вкусами
		FROM 
			feedback f 
		JOIN  
			feedback f2 ON (f2.book_id = f.book_id 
	    					AND f2.rating = f.rating)
		WHERE f.user_id = for_user_id 
	   		 AND f2.user_id <> for_user_id) -- исключим себя
	ORDER BY RAND() 
	LIMIT 10;
		
  END//
  
delimiter ; 

CALL recommendations(56);

-- 3. функция, определяющая дату окончания подписки определенного пользователя

DROP FUNCTION IF EXISTS subs_end;
delimiter //
CREATE FUNCTION subs_end (user_id BIGINT) -- передаем id пользователя
RETURNS DATETIME READS SQL DATA
BEGIN
	DECLARE subs_id int;
	DECLARE start_date datetime;
	DECLARE subs_end datetime;
	
	SET subs_id = (					-- находим id тарифного плана подписки
	SELECT subscription_plan_id FROM users 
	WHERE id = user_id
	);

	SET start_date = (				-- выбираем дату оформления подписки
	SELECT subs_date FROM users 
	WHERE id = user_id
	);

	CASE							-- исходя из тарифного плана определяем дату окончания подписки с помощью оператора case 
	 	WHEN subs_id IN (1,4,7) THEN SET subs_end = (start_date + INTERVAL 1 MONTH);
	 	WHEN subs_id IN (2,5,8) THEN SET subs_end = (start_date + INTERVAL 3 MONTH);
	 	WHEN subs_id IN (3,6,9) THEN SET subs_end = (start_date + INTERVAL 1 YEAR);
	 ELSE SET subs_end = NULL ; -- если у пользователя нет подписки возвращаем null
	END CASE;
RETURN subs_end;
	
END//

delimiter ;

SELECT subs_end(67);

-- представления

-- 1. тарифные планы со скидкой 25%

CREATE OR REPLACE VIEW v_sales_25 AS 
SELECT 
	s.name,
	sp.period,
	round(sp.price * 0.75) sale_price
FROM 
	subscription_plans sp 
JOIN 
	subscriptions s ON sp.subscription_id = s.id; 

SELECT sale_price FROM v_sales_25;

-- 2. дата окончания подписки для каждого пользователя, 
	-- используем, чтобы найти пользователей с истекшими подписками 
	-- и пользователей, чья подписка истекает через 14 дней


CREATE OR REPLACE VIEW v_subscription_end AS
SELECT 				-- выборка подписок на месяц
	u.id user_id,
	u.email,
	s.name subscription,
	(u.subs_date + INTERVAL 1 MONTH) AS subs_end
FROM 
	users u
JOIN 
	subscription_plans sp  ON u.subscription_plan_id = sp.id 
JOIN subscriptions s ON sp.subscription_id = s.id
WHERE u.subscription_plan_id IN (1, 4, 7)

	UNION 
	
SELECT 				-- выборка подписок на 3 месяца
	u.id user_id,
	u.email,
	s.name subscription,
	(u.subs_date + INTERVAL 3 MONTH) AS subs_end
FROM 
	users u
JOIN 
	subscription_plans sp  ON u.subscription_plan_id = sp.id 
JOIN subscriptions s ON sp.subscription_id = s.id
WHERE u.subscription_plan_id IN (2, 5, 8)

	UNION 
	
SELECT 					-- выборка подписок на 1 год
	u.id user_id,
	u.email,
	s.name subscription,
	(u.subs_date + INTERVAL 1 YEAR) AS subs_end
FROM 
	users u
JOIN 
	subscription_plans sp  ON u.subscription_plan_id = sp.id 
JOIN subscriptions s ON sp.subscription_id = s.id
WHERE u.subscription_plan_id IN (3, 6, 9)

ORDER BY subs_end;

-- используя представление, находим сколько дней осталось до окончания подписки
SELECT 
	user_id, 
	subs_end,
	(TO_DAYS(subs_end) - TO_DAYS(now())) days_left -- отрицательное значение - подписка истекла
FROM v_subscription_end
HAVING days_left < 14;

-- триггеры
		-- 1.
	-- проверяем подписку перед обновлением тарифного плана:
	-- если подписка подключена, устанавливаем дату начала подписки текущей датой,
	-- если подписки нет, то устанавливаем null в дату начала подписки
DROP TRIGGER IF EXISTS check_subscription;
delimiter //
CREATE TRIGGER check_subscription BEFORE UPDATE ON users
FOR EACH ROW 
BEGIN  
	IF 
	 	NEW.subscription_plan_id IS NOT NULL  
	THEN 
		SET NEW.subs_date = CURRENT_TIMESTAMP() ;
	ELSEIF 
		NEW.subscription_plan_id IS NULL  
	THEN 
		SET NEW.subs_date = null ;
	END IF;
END //

delimiter ;
 
UPDATE users 
	SET 
		subscription_plan_id = 2
	WHERE id = 3;

UPDATE users 
	SET 
		subscription_plan_id = null
	WHERE id = 15;


	-- 	2.
	-- аудиокниги доступны только в подписке премиум (id=3)
	-- запрещаем вставку аудиокниги с другой подпиской
DROP TRIGGER IF EXISTS check_audiobook_subscription_id;
delimiter //
CREATE TRIGGER check_audiobook_subscription_id BEFORE INSERT ON books 
FOR EACH ROW 
BEGIN  
	IF 
	 	(NEW.`type` = 'audio' AND NEW.subscription_id <> 3)
	THEN 
	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'INSERT CANCELED. FIELD subscription_id HAVE INCORRECT VALUE';
	END IF;
END //

delimiter ;

INSERT INTO books (name, `type`, subscription_id) VALUES ('firefly', 'audio', 2);
INSERT INTO books (name, `type`, subscription_id) VALUES ('greekfrog', 'audio', 3);