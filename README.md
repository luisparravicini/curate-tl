# curate-tl

The script was written to curate my own tweets, it *might* be useful to someone else.

It needs [twurl](https://github.com/twitter/twurl), read it's documentation to install and setup it up. Or follow the [tutorial on Twitter](https://developer.twitter.com/en/docs/tutorials/using-twurl).

After having twurl running, copy `demo-conf.yaml` to `conf.yaml` and edit it with our data.

`curate-tl.rb` does the following:

 * Asks if you want to delete your likes
 * Retrieves all the tweets it can, it stores them in `tweets.json`
 * It lists tweets that match the criteria for deletion and asks if you want to proceed. After removing them, it continues with the next batch.


 It accepts the following parameters:

 `-r` / `--resume` Reads the tweets from the local cache (`tweets.json`) instead of retrieving them with the api

`-m` Only deletes tweets that are RTs and start mentioning a username

`-a PATH` Reads tweets and likes from the [archive downloaded from Twitter](https://help.twitter.com/en/managing-your-account/how-to-download-your-twitter-archive). Sometimes, the api doesn't return all the old tweets, so this is a way to access those old tweets. Use the path where the zip was decompressed.

`-o days` Only evaluate tweets older (in days) than the value specified.
