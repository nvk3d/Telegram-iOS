# README #

Я дико извиняюсь за непонятки со стримом и с ссылкой на сторонний ресурс. 
Дело в том, что я начал делать задание не посмотрев ваш пример. Так как я до этого работал 
со стримами, я знал, что обычно используют несколько дорожек для аудио и видео, поэтому
я подобрал сторонний файл и начал выполнять задание. 

Моя библиотека работает с сегментами в формате .ts. Отдельно тащит аудио и видео,
даже получается воспроизводить без лагов 4k видео, только я его отключил для этого задания,
тк не вывозило ускорение видео. Если вам это интересно посмотреть, то можете закомментировать 
342 строку в файле StreamSession.swift

Понимаю, что скорее всего за такую реализацию мне грозит дисквал, но думаю, что такая библиотека
вам может быть полезна, поэтому и решил скинуть этот код.

К сожалению, я не успел адаптировать плеер под ваш формат.

=======

I apologize profusely for the confusion with the stream and the link to the third-party resource.
The thing is that I started doing the task without looking at your sample. Since I had worked with 
streams before, I knew that they usually use several tracks for audio and video, so
I picked up a third-party file and started doing the task.

My library works with segments in the .ts format. It separately pulls audio and video,
it even manages to play 4k video without lags, only I disabled it for this task,
because video acceleration did not work. If you are interested in seeing this, you can comment out
line 342 in the StreamSession.swift file

I understand that most likely I will be disqualified for such an implementation, but I think that 
such a library can be useful to you, so I decided to push this code.

Unfortunately, I did not have time to adapt the player to your format.
