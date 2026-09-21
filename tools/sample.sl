# SimpleLang smoke test

to double with n
  give n * 2
end

to greet with who, count
  repeat count times
    say "hello " + who
  end
end

set score to 0
for i from 1 to 5
  set score to score + i
end
say "score is", score

if score > 10 then
  say "big score"
else
  say "small score"
end

say "double 21 is " + double(21)
call greet with "kai", 2

set things to [1, 2, 3]
set things[2] to 99
say "list:", things
say "second is " + things[2]
say "length is " + len(things)

set n to 3
while n > 0 do
  say "countdown " + n
  set n to n - 1
end

set word to "SimpleLang"
say upper(word) + " has " + len(word) + " letters"

ask answer "how many?"
say "you said " + answer

set total to 0
for i from 1 to 10
  if i % 2 == 0 then
    set total to total + i
  end
end
say "even total is " + total

set found to 0
for i from 1 to 20
  if i > 15 then
    set found to i
    stop
  end
end
say "stopped at " + found

if score > 100 and score < 200 then
  say "never"
else if score > 10 or false then
  say "else-if works"
end
