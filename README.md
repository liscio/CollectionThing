#  A CollectionView-y Thing For SwiftUI

This is a sketch of an approach that lets you put a _ton_ of items into a SwiftUI `ScrollView` while maintaining decent performance. Even with *50,000* elements, the view appears almost immediately, and memory usage is not terrible.

No weird uses of `DispatchQueue.async`, and (as far as I am concerned) it doesn't _really_ contain any gross hacks. Beauty is in the eye of the beholder, etc…

## How does it work?

It's a lot like a `{UI,NS}CollectionView` in that you're responsible for maintaining the layout logic of views by yourself. But—as you can see—the `WrappedLayout` struct that I supplied isn't overly complicated. It just takes your model objects, and packages them up into rows. Those rows have `frame`s, and the layout itself has an overall `contentSize`.

The `ContentView` calculates the current `visibleRect` using `PreferenceKey`s, and on changing preference values, the `layout` is queried for the rows that overlap the current `visibleRect` (plus a bit of "slop factor" to reduce flashing—play around for your own needs).

A `@State` variable tracks the current set of `visibleRows`, and those are only updated when we start to get close to the edge of the rows we've already cached.

When everything's laid out, the content of your `ScrollView` will look like this:

```
+++++++++++++++++++++++++
|     Color(.clear)     |
|                       |
|                       |
+++++++++++++++++++++++++
|  VStack(visibleRows)  |
|                       +++
|                       | |
|                       | | visibleRect 
|                       | |
|                       +++
|                       |
+++++++++++++++++++++++++
|                       |
|                       |
|                       |
+++++++++++++++++++++++++
```

Effectively, the "magic" here is in the fact that a `VStack` contains _only_ as many rows as you'll need, and no more. It is positioned at the same spot where those visible rows would normally appear if you had a `VStack` containing _all_ of the rows in the layout. It looks an awful lot like the way `UICollectionView` works—only creating views that are visible, while defining a larger content area.

As you scroll, the inner `VStack` is _only_ updated when the `visibleRows` change. So you'll experience the native scrolling speed until it is deemed that new rows need to get "faulted in" to the view. Even then, a reasonably new device should be able to retain smooth scrolling since `SwiftUI` can generate that new set of views very quickly. _Much faster_ than trying to calculate the viewport for the entire data set.

When the `visibleRows` _do_ change, they are mostly the same—the amount of churn inside the inner `VStack` _should_ be minimal because the `Row`s themselves are `Identifiable`.

## Keys to Performance

There are a few things that (I think) are important here:

1. The root-level `@ObservedObject` whose `value` does not change
2. The `@State` variables that _only_ get set _when necessary_
3. `Row` values that are identifiable, used in concert with the inner `VStack` to try and keep churn to a minimum

## Known Issues

The implementation is obviously incomplete, and there many details that you'll need to get sorted out.

Stuff like:

* Incorporating the `safeAreaInsets` into your layout (which are readable from the outer `GeometryProxy` on the `ScrollView`)
* Dealing with rotation
* Insertion/removal animations
* Being smarter/faster about querying your `Row`s
* Selection management

Plenty of exercises for the reader. :)

## Credits/etc.

Thanks to the folks at [swiftui-lab](https://swiftui-lab.com) for [their post](https://swiftui-lab.com/scrollview-pull-to-refresh/) that gave me a few nifty ideas that helped me narrow down my initial work on this.

If you find this repo helpful, that's great! To repay me, you can go and check out [Capo](http://capoapp.com). Then, tell your friends to do the same.

Also, pull requests are welcome if you find any opportunities for making this go _even faster_ without resorting to anything gross. 
